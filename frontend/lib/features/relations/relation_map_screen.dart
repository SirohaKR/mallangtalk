import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../home/friends_screen.dart';
import '../library/character_library.dart';
import '../../shared/utils/korean.dart';

/// 관계 한 줄: [from]의 주변 인물로 [to]가 [role]로 연결됨
class Relation {
  final CharacterModel from;
  final CharacterModel to;
  final String role;
  const Relation(this.from, this.to, this.role);
}

/// 내가 만든 캐릭터들과, 그 사이에 이어 둔 관계 (주변 인물에 내 캐릭터를 연결한 것)
final myRelationsProvider = Provider<(List<CharacterModel>, List<Relation>)>((ref) {
  final mine = [
    for (final e in ref.watch(characterLibraryProvider))
      if (e.source == CharacterSource.created) e.bundle.character,
  ];
  final byId = {for (final c in mine) c.id: c};
  final relations = [
    for (final c in mine)
      for (final cast in c.extraCast)
        if (byId[cast.characterId] case final to?) Relation(c, to, cast.role),
  ];
  return (mine, relations);
});

/// [초보자 노트] 관계도: 내가 만든 캐릭터끼리 설정을 이어서 한눈에 봐요.
/// 관계는 캐릭터 설정의 '주변 인물'에 저장돼서, 상세 화면과 AI 자유대화에도 그대로 쓰여요.
class RelationMapScreen extends ConsumerWidget {
  const RelationMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (mine, relations) = ref.watch(myRelationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('관계도')),
      floatingActionButton: mine.length < 2
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surfaceWhite,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _LinkEditor(characters: mine),
              ),
              icon: const Icon(Icons.link_rounded),
              label: const Text('관계 잇기'),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 760),
          child: mine.length < 2
              ? const Padding(
                  padding: AppSpacing.screenPadding,
                  child: Text('내가 만든 캐릭터가 둘 이상이면 서로 관계를 이을 수 있어요',
                      textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
                  children: [
                    AspectRatio(aspectRatio: 1, child: _RelationGraph(characters: mine, relations: relations)),
                    const SizedBox(height: AppSpacing.md),
                    Text(relations.isEmpty ? '아직 이어 둔 관계가 없어요' : '관계 ${relations.length}',
                        style: AppTextStyles.messageTime),
                    for (final r in relations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CharacterAvatar(character: r.from, radius: 18),
                        title: Text.rich(TextSpan(children: [
                          TextSpan(text: r.from.name, style: AppTextStyles.speakerName),
                          const TextSpan(text: '  →  '),
                          TextSpan(text: r.to.name, style: AppTextStyles.speakerName),
                        ])),
                        subtitle: Text(r.role.isEmpty ? '관계를 적지 않았어요' : '${josa(r.to.name, '은', '는')} ${r.from.name}의 ${r.role}', style: AppTextStyles.systemNotice),
                        trailing: IconButton(
                          tooltip: '관계 끊기',
                          icon: const Icon(Icons.link_off_rounded, size: 20),
                          onPressed: () => ref.read(characterLibraryProvider.notifier).updateCharacter(
                                r.from.copyWith(extraCast: [
                                  for (final e in r.from.extraCast)
                                    if (e.characterId != r.to.id) e,
                                ]),
                              ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 캐릭터를 원 위에 늘어놓고 관계를 선으로 이음. 캐릭터를 누르면 프로필
class _RelationGraph extends ConsumerWidget {
  const _RelationGraph({required this.characters, required this.relations});

  final List<CharacterModel> characters;
  final List<Relation> relations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      const avatar = 26.0;
      final center = Offset(size.width / 2, size.height / 2);
      final radius = min(size.width, size.height) / 2 - avatar - 18;
      final positions = <String, Offset>{
        for (var i = 0; i < characters.length; i++)
          characters[i].id: center +
              Offset.fromDirection(-pi / 2 + 2 * pi * i / characters.length, characters.length == 1 ? 0 : radius),
      };
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _LinkPainter(relations: relations, positions: positions)),
          ),
          for (final c in characters)
            Positioned(
              left: positions[c.id]!.dx - avatar - 12,
              top: positions[c.id]!.dy - avatar,
              width: (avatar + 12) * 2,
              child: GestureDetector(
                onTap: () {
                  final entry = ref.read(characterLibraryProvider.notifier).byId(c.id);
                  if (entry != null) showCharacterProfile(context, entry);
                },
                child: Column(
                  children: [
                    CharacterAvatar(character: c, radius: avatar),
                    const SizedBox(height: 2),
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.speakerName),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _LinkPainter extends CustomPainter {
  _LinkPainter({required this.relations, required this.positions});

  final List<Relation> relations;
  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.primaryPink.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    // A→B와 B→A가 둘 다 있으면 한 줄에 두 관계를 위아래로
    final drawn = <String, int>{};
    for (final r in relations) {
      final a = positions[r.from.id];
      final b = positions[r.to.id];
      if (a == null || b == null) continue;
      final key = ([r.from.id, r.to.id]..sort()).join('|');
      final nth = drawn[key] = (drawn[key] ?? -1) + 1;
      if (nth == 0) canvas.drawLine(a, b, line);
      if (r.role.isEmpty) continue;
      final text = TextPainter(
        text: TextSpan(
          text: '${r.from.name}의 ${r.role}',
          style: AppTextStyles.messageTime.copyWith(color: AppColors.textPrimary, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      final mid = Offset.lerp(a, b, 0.5)! + Offset(0, nth * 18.0 - 9);
      final rect = Rect.fromCenter(center: mid, width: text.width + 10, height: text.height + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = AppColors.surfaceWhite.withValues(alpha: 0.92),
      );
      text.paint(canvas, rect.topLeft + const Offset(5, 2));
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => old.relations != relations || old.positions != positions;
}

/// 관계 잇기: 누가, 누구에게, 어떤 사이인지. 고른 캐릭터의 주변 인물에 저장
class _LinkEditor extends ConsumerStatefulWidget {
  const _LinkEditor({required this.characters});

  final List<CharacterModel> characters;

  @override
  ConsumerState<_LinkEditor> createState() => _LinkEditorState();
}

class _LinkEditorState extends ConsumerState<_LinkEditor> {
  late String _from = widget.characters[0].id;
  late String _to = widget.characters[1].id;
  final _role = TextEditingController();
  bool _both = false;
  final _backRole = TextEditingController();

  @override
  void dispose() {
    _role.dispose();
    _backRole.dispose();
    super.dispose();
  }

  CharacterModel _byId(String id) => widget.characters.firstWhere((c) => c.id == id);

  Future<void> _link(CharacterModel from, CharacterModel to, String role) async {
    final cast = [
      for (final e in from.extraCast)
        if (e.characterId != to.id) e,
      ExtraCast(name: to.name, role: role.trim(), characterId: to.id),
    ];
    await ref.read(characterLibraryProvider.notifier).updateCharacter(from.copyWith(extraCast: cast));
  }

  Widget _picker(String label, String value, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final c in widget.characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (v) => setState(() => onChanged(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final from = _byId(_from);
    final to = _byId(_to);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('관계 잇기', style: AppTextStyles.appBarTitle),
            const SizedBox(height: 4),
            const Text('고른 캐릭터의 주변 인물에 저장돼서 상세 화면과 AI 자유대화에도 쓰여요',
                style: AppTextStyles.systemNotice),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _picker('누가', _from, (v) => _from = v)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded)),
                Expanded(child: _picker('누구를', _to, (v) => _to = v)),
              ],
            ),
            TextField(
              controller: _role,
              decoration: InputDecoration(
                labelText: '${from.name}에게 ${to.name}는(은)',
                hintText: '예: 소꿉친구, 짝사랑 상대, 룸메이트',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _both,
              title: Text('${to.name} 쪽에서도 잇기', style: AppTextStyles.chatBubbleBody),
              onChanged: (v) => setState(() => _both = v ?? false),
            ),
            if (_both)
              TextField(
                controller: _backRole,
                decoration: InputDecoration(labelText: '${to.name}에게 ${from.name}는(은)'),
              ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _from == _to
                  ? null
                  : () async {
                      await _link(from, to, _role.text);
                      if (_both) await _link(ref.read(characterLibraryProvider.notifier).byId(to.id)!.bundle.character, from, _backRole.text);
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text(_from == _to ? '서로 다른 캐릭터를 골라 주세요' : '잇기'),
            ),
          ],
        ),
      ),
    );
  }
}
