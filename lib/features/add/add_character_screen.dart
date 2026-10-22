import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';
import '../../shared/widgets/character_avatar.dart';
import '../library/character_library.dart';
import '../studio/character_import.dart';
import '../studio/script_workbook.dart';
import '../studio/studio_screen.dart';

/// [초보자 노트] '캐릭터 추가' 탭: 받아오기(기본 캐릭터·파일) / 만들기(엑셀 대본·AI 생성)
class AddCharacterScreen extends StatelessWidget {
  const AddCharacterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('캐릭터 추가'),
          bottom: TabBar(
            labelStyle: AppTextStyles.choiceButton,
            unselectedLabelStyle: AppTextStyles.choiceButton.copyWith(color: AppColors.textSecondary),
            indicatorColor: AppColors.primaryPink,
            tabs: const [Tab(text: '받아오기'), Tab(text: '만들기')],
          ),
        ),
        body: const TabBarView(
          children: [ImportCharacterTab(), StudioScreen()],
        ),
      ),
    );
  }
}

/// 받아오기: 앱 기본 캐릭터 + 친구가 보내 준 캐릭터 파일(.json) 또는 엑셀 대본(.xlsx)
class ImportCharacterTab extends ConsumerStatefulWidget {
  const ImportCharacterTab({super.key});

  @override
  ConsumerState<ImportCharacterTab> createState() => _ImportCharacterTabState();
}

class _ImportCharacterTabState extends ConsumerState<ImportCharacterTab> {
  ScriptWorkbookResult? _picked;
  List<String> _errors = const [];

  Future<void> _pickFile() async {
    final file = await FileIO.pick(extensions: ['json', 'xlsx']);
    if (file == null) return;
    setState(() {
      try {
        _picked = readCharacterFile(file);
        _errors = const [];
      } on ScriptWorkbookException catch (e) {
        _picked = null;
        _errors = e.errors;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final builtins = ref.watch(builtinBundlesProvider).valueOrNull ?? const [];
    final mine = ref.watch(characterLibraryProvider).map((e) => e.id).toSet();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('기본 캐릭터', style: AppTextStyles.appBarTitle),
            const SizedBox(height: 4),
            const Text('공개 캐릭터 둘러보기는 서버가 생기면 여기에 열려요.', style: AppTextStyles.systemNotice),
            const SizedBox(height: AppSpacing.sm),
            for (final bundle in builtins)
              _CharacterCard(
                bundle: bundle,
                added: mine.contains(bundle.character.id),
                onAdd: () => _add(bundle, CharacterSource.builtin),
              ),
            const SizedBox(height: AppSpacing.xl),
            const Text('파일로 받아오기', style: AppTextStyles.appBarTitle),
            const SizedBox(height: 4),
            const Text(
              '다른 사람이 보내 준 캐릭터 파일(.json)이나 엑셀 대본(.xlsx)을 열어요.',
              style: AppTextStyles.systemNotice,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('파일 고르기'),
              onPressed: _pickFile,
            ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ProblemList(title: '이 파일은 열 수 없어요', items: _errors, isError: true),
            ],
            if (_picked != null) ...[
              const SizedBox(height: AppSpacing.md),
              _CharacterCard(
                bundle: _picked!.bundle,
                added: false,
                replaces: mine.contains(_picked!.bundle.character.id),
                onAdd: () => _add(_picked!.bundle, CharacterSource.imported, clearPicked: true),
              ),
              if (_picked!.warnings.isNotEmpty)
                ProblemList(title: '확인해 보면 좋은 점', items: _picked!.warnings),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _add(ScenarioBundle bundle, CharacterSource source, {bool clearPicked = false}) async {
    await addCharacterAndAnnounce(context, ref, bundle, source);
    if (clearPicked && mounted) setState(() => _picked = null);
  }
}

/// 내 캐릭터에 넣고 '채팅하기' 바로가기를 띄움 (받아오기·만들기 공통)
Future<void> addCharacterAndAnnounce(
  BuildContext context,
  WidgetRef ref,
  ScenarioBundle bundle,
  CharacterSource source,
) async {
  await ref.read(characterLibraryProvider.notifier).add(bundle, source);
  if (!context.mounted) return;
  final router = GoRouter.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${bundle.character.name}을(를) 내 캐릭터에 추가했어요'),
      action: SnackBarAction(
        label: '채팅하기',
        onPressed: () {
          ref.read(chatRoomsProvider.notifier).open(bundle.character.id);
          router.push('/chat/${bundle.character.id}');
        },
      ),
    ),
  );
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.bundle,
    required this.added,
    required this.onAdd,
    this.replaces = false,
  });

  final ScenarioBundle bundle;
  final bool added;
  final bool replaces;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = bundle.character;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CharacterAvatar(character: c, radius: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                    if (c.statusMessage.isNotEmpty)
                      Text(c.statusMessage, style: AppTextStyles.systemNotice, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(ScenarioSummary.of(bundle).line, style: AppTextStyles.messageTime.copyWith(height: 1.4)),
          if (c.affectionStages.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '단계: ${c.affectionStages.map((s) => s.stageLabel).join(' → ')}',
              style: AppTextStyles.messageTime.copyWith(height: 1.4),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          added
              ? const OutlinedButton(onPressed: null, child: Text('추가됨'))
              : ElevatedButton(
                  onPressed: onAdd,
                  child: Text(replaces ? '내 캐릭터에 덮어쓰기' : '내 캐릭터에 추가'),
                ),
        ],
      ),
    );
  }
}

/// 오류·주의 목록 카드
class ProblemList extends StatelessWidget {
  const ProblemList({super.key, required this.title, required this.items, this.isError = false});

  final String title;
  final List<String> items;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.primaryPink : AppColors.affectionWarm;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.speakerName.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          for (final item in items.take(12))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $item', style: AppTextStyles.systemNotice),
            ),
          if (items.length > 12)
            Text('그 외 ${items.length - 12}개', style: AppTextStyles.systemNotice),
        ],
      ),
    );
  }
}
