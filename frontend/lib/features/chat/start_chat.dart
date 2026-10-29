import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../help/help_guide.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import 'chat_notifier.dart';
import 'service_messages.dart';
import '../../shared/utils/korean.dart';

/// [초보자 노트] 캐릭터와의 대화방을 엽니다.
/// 처음 대화하는 캐릭터면 스토리/자유대화 중 어떻게 시작할지와 '이 대화에서 쓸 내 별명'을 묻고
/// (설정의 기본 별명이 미리 들어감), 정한 뒤에 대화가 시작됩니다. 이미 대화방이 있으면 가장 최근 방으로 가요.
/// [roomId]를 주면 그 방(채팅 목록에서 누른 방)으로 바로 갑니다.
/// 상태는 [context]가 속한 ProviderScope에서 직접 읽어요. 프로필 시트처럼 먼저 닫히는 화면의 ref를 쓰면
/// 시트가 닫히는 순간 ref가 사라져서 대화방으로 넘어가지 못하거든요.
Future<void> openChat(BuildContext context, CharacterModel character, {String? roomId}) async {
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final rooms = container.read(chatRoomsProvider.notifier);
  var room = roomId ?? rooms.latestOf(character.id);
  if (room == null || container.read(chatPrefsProvider(character.id)).nickname == null) {
    final profile = await _askProfile(context, character, isFirstTime: true);
    if (profile == null) return;
    room ??= profile.free ? freeRoomId(character.id) : character.id;
  }
  rooms.open(room);
  final free = isFreeRoom(room);
  if (!free) container.read(chatRoomProvider(room).notifier).begin();
  router.push(free ? '/free/${character.id}' : '/chat/${character.id}');
}

/// 이 캐릭터와의 대화에서 불릴 내 별명과 내 설정(페르소나)을 묻고 저장합니다. 취소하면 null
Future<String?> askChatNickname(
  BuildContext context,
  CharacterModel character, {
  bool isFirstTime = false,
}) async =>
    (await _askProfile(context, character, isFirstTime: isFirstTime))?.nickname;

Future<_ChatProfile?> _askProfile(
  BuildContext context,
  CharacterModel character, {
  required bool isFirstTime,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final current =
      container.read(chatPrefsProvider(character.id)).nickname ?? container.read(userProfileProvider).nickname;
  final chooseMode = isFirstTime && !character.isService;
  final dialog = _NicknameDialog(
    character: character,
    initial: current,
    initialPersona: container.read(chatPersonaProvider(character.id)),
    initialInfo: container.read(serviceUserInfoProvider(character.id)),
    isFirstTime: isFirstTime,
    chooseMode: chooseMode,
  );
  // 처음 대화(이야기 말랑이)는 아래에서 올라오는 시트에서 스토리/자유대화를 고름. 별명만 바꿀 땐 작은 창
  final result = chooseMode
      ? await showModalBottomSheet<_ChatProfile>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.surfaceWhite,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => dialog,
        )
      : await showDialog<_ChatProfile>(context: context, builder: (_) => dialog);
  if (result == null) return null;
  final prefs = container.read(chatPrefsProvider(character.id).notifier);
  await prefs.setNickname(result.nickname);
  if (character.isService) {
    // 서비스 말랑이는 페르소나 대신 봇이 쓸 내 정보(띠·생일 등)만 받음
    await container.read(serviceUserInfoProvider(character.id).notifier).save(result.info);
    return result;
  }
  await prefs.setPersona(result.persona);
  if (result.saveAsDefault) await container.read(userProfileProvider.notifier).savePersona(result.persona);
  return result;
}

typedef _ChatProfile = ({String nickname, String persona, bool saveAsDefault, bool free, Map<String, String> info});

/// 캐릭터별 대화 속도 고르기
Future<void> pickChatTempo(BuildContext context, CharacterModel character) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, ref, _) {
        final tempo = ref.watch(chatPrefsProvider(character.id)).tempo;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${character.name} 대화 속도', style: AppTextStyles.appBarTitle),
                const SizedBox(height: 4),
                Text(
                  '${character.name}의 타자 스타일은 "${TypingStyle.closest(character.typingSpeedMultiplier).label}"이에요. '
                  '여기서 고른 속도가 그 위에 곱해져요.',
                  style: AppTextStyles.systemNotice,
                ),
                const SizedBox(height: 8),
                for (final option in ChatTempoOption.all)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      ref.read(chatPrefsProvider(character.id).notifier).setTempo(option.tempo);
                      Navigator.pop(sheetContext);
                    },
                    leading: Icon(
                      tempo == option.tempo ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: tempo == option.tempo ? AppColors.primaryPink : AppColors.textMuted,
                    ),
                    title: Text(option.label),
                    subtitle: Text(option.note, style: AppTextStyles.systemNotice),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 별명·페르소나 입력 창. 입력칸 컨트롤러를 창이 직접 들고 있다가 닫히는 애니메이션이 끝난 뒤 정리합니다.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({
    required this.character,
    required this.initial,
    required this.initialPersona,
    this.initialInfo = const {},
    required this.isFirstTime,
    this.chooseMode = false,
  });

  final CharacterModel character;
  final String initial;
  final String initialPersona;
  final Map<String, String> initialInfo;
  final bool isFirstTime;

  /// 스토리/자유대화 고르는 카드를 보일지 (처음 대화 + 이야기 말랑이)
  final bool chooseMode;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  late final _persona = TextEditingController(text: widget.initialPersona);
  bool _saveAsDefault = false;
  bool _free = false;
  String? _error;

  /// 처음 안내 4단계: 대화 시작 창 위 말랑이 말풍선 (처음 한 번)
  /// (서비스 말랑이는 작은 창 위에 따로 한 번)
  String get _tipId => widget.character.isService ? HelpGuide.startService : HelpGuide.start;
  late bool _tip = widget.isFirstTime &&
      HelpGuide.autoShow &&
      !ProviderScope.containerOf(context, listen: false).read(helpSeenProvider).contains(_tipId);

  void _closeTip() {
    if (!_tip) return;
    ProviderScope.containerOf(context, listen: false).read(helpSeenProvider.notifier).mark([_tipId]);
    setState(() => _tip = false);
  }

  Widget _tipCard() {
    final service = widget.character.isService;
    return Container(
      key: const ValueKey('help_start_tip'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3F7),
        border: Border.all(color: const Color(0xFFF0CFDB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MallangSays(
            service
                ? '서비스 말랑이는 정해진 때마다 **먼저 톡**을 보내 줘. 필요한 내 정보만 적어 두면 돼!'
                : '대화하기 전에 **대화 방식**을 골라. 둘 다 해 봐도 돼, 대화방이 따로라 서로 영향이 없어.',
            size: 40,
          ),
          if (service) ...[
            const HelpLine(null, '아래 정보는 톡 문구에 들어가. 나중에 대화방 메뉴의 **내 별명·정보**에서 바꿀 수 있어', tag: '내 정보'),
          ] else ...[
            const HelpLine(null, '선택지를 골라 이야기를 따라가. 사진을 모으고 엔딩을 볼 수 있어. 키 없어도 돼!', tag: '스토리'),
            const HelpLine(null, '하고 싶은 말을 직접 써. AI 키가 필요하고 호감도·엔딩은 없어', tag: '자유대화'),
            const HelpLine(null, '이 대화에서만 쓸 별명과 나에 대한 설정을 바꿀 수 있어', tag: '내 설정'),
          ],
          Row(children: [
            if (!service) const HelpDots(3),
            const Spacer(),
            TextButton(
              key: const ValueKey('help_start_ok'),
              onPressed: _closeTip,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB83B66)),
              child: const Text('알겠어'),
            ),
          ]),
        ],
      ),
    );
  }

  /// 서비스 말랑이가 물어보는 정보 (칸 이름 → 값)
  late final Map<String, String> _info = {...widget.initialInfo};
  late final _infoText = {
    for (final f in _askFields)
      if (serviceAskChoices(widget.character.service!, f).isEmpty)
        f: TextEditingController(text: widget.initialInfo[f] ?? ''),
  };

  List<String> get _askFields => [
        for (final f in widget.character.service?.ask ?? const <String>[])
          if (f.trim().isNotEmpty) f.trim()
      ];

  @override
  void dispose() {
    _controller.dispose();
    _persona.dispose();
    for (final c in _infoText.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return setState(() => _error = '별명을 적어 주세요');
    _closeTip();
    for (final e in _infoText.entries) {
      _info[e.key] = e.value.text.trim();
    }
    Navigator.pop<_ChatProfile>(context, (
      nickname: text,
      persona: _persona.text.trim(),
      saveAsDefault: _saveAsDefault,
      free: _free,
      info: {for (final f in _askFields) f: _info[f] ?? ''},
    ));
  }

  /// 서비스 말랑이: 페르소나 대신 봇이 쓸 내 정보 칸들
  List<Widget> _serviceFields() {
    final name = widget.character.name;
    final config = widget.character.service!;
    final fields = _askFields;
    if (fields.isEmpty) return const [];
    return [
      const SizedBox(height: 4),
      Text('${josa(name, '이', '가')} 톡을 보낼 때 쓰는 내 정보예요. 맞는 걸 골라 주세요.', style: AppTextStyles.systemNotice),
      for (final f in fields) ...[
        const SizedBox(height: 12),
        if (serviceAskChoices(config, f) case final choices when choices.isNotEmpty) ...[
          Text(f, style: AppTextStyles.speakerName),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in choices)
                ChoiceChip(
                  key: ValueKey('ask_${f}_$c'),
                  label: Text(c),
                  selected: _info[f] == c,
                  showCheckmark: false,
                  selectedColor: Color.lerp(AppColors.surfaceWhite, AppColors.primaryPink, 0.2),
                  onSelected: (on) => setState(() => _info[f] = on ? c : ''),
                ),
            ],
          ),
        ] else
          TextField(
            key: ValueKey('ask_$f'),
            controller: _infoText[f],
            maxLength: 40,
            decoration: InputDecoration(labelText: f, hintText: f.contains('생일') ? '예: 3월 2일' : null),
          ),
      ],
      const SizedBox(height: 6),
      const Text('나중에 대화방 메뉴의 \'내 별명·정보\'에서 바꿀 수 있어요', style: AppTextStyles.messageTime),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.character.name;
    final fields = <Widget>[
      if (_tip && !widget.chooseMode) _tipCard(),
      Text(
        '${josa(name, '이', '가')} 나를 이렇게 불러요. 설정의 기본 별명이 들어가 있고, 이 대화에서만 바꿀 수 있어요.',
        style: AppTextStyles.systemNotice,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _controller,
        autofocus: !widget.chooseMode,
        maxLength: 12,
        decoration: InputDecoration(labelText: '내 별명', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      if (widget.character.isService)
        ..._serviceFields()
      else ...[
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('persona_field'),
          controller: _persona,
          minLines: widget.chooseMode ? 2 : 3,
          maxLines: null,
          maxLength: 400,
          decoration: InputDecoration(
            labelText: '내 설정 (페르소나)',
            alignLabelWithHint: true,
            hintText: '예: 24살, 같은 과 동기. 무뚝뚝한데 정이 많음. ${josa(name, '과', '와')}는 1년째 친구',
            hintMaxLines: 3,
          ),
        ),
        const Text('안 적어도 돼요. AI 자유대화에서 캐릭터가 이 설정을 알고 대화해요', style: AppTextStyles.systemNotice),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _saveAsDefault,
          onChanged: (v) => setState(() => _saveAsDefault = v ?? false),
          title: const Text('다른 캐릭터에도 기본으로 쓰기'),
        ),
      ],
    ];

    if (!widget.chooseMode) {
      return AlertDialog(
        title: Text(widget.isFirstTime ? '${josa(name, '과', '와')} 대화 시작' : '이 대화에서 나'),
        content: SingleChildScrollView(
          child:
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(onPressed: _submit, child: Text(widget.isFirstTime ? '대화 시작' : '저장')),
        ],
      );
    }

    // 처음 대화: 스토리/자유대화 카드 + 내 별명·설정 + 시작 버튼 (와이어프레임 7-1)
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text('${josa(name, '과', '와')} 어떻게 대화할까요?', style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            if (_tip) _tipCard(),
            _ModeCard(
              key: const ValueKey('start_mode_story'),
              icon: Icons.auto_stories_rounded,
              title: '스토리',
              note: '제작자가 쓴 이야기를 따라가요. 선택지로 가까워지고 사진을 모으고 엔딩이 있어요.',
              chips: const ['키 없어도 돼요'],
              on: !_free,
              onTap: () => setState(() => _free = false),
            ),
            const SizedBox(height: 8),
            _ModeCard(
              key: const ValueKey('start_mode_free'),
              icon: Icons.forum_rounded,
              title: '자유대화',
              note: '아무 말이나 해요. ${josa(name, '이', '가')} AI로 답하고 어울리는 순간엔 사진도 보내요. 호감도와 엔딩은 없어요.',
              chips: const ['AI 키 필요'],
              on: _free,
              onTap: () => setState(() => _free = true),
            ),
            const SizedBox(height: 6),
            const Text('두 대화방은 따로 이어지고, 다른 쪽은 나중에 대화방 메뉴에서 시작할 수 있어요', style: AppTextStyles.messageTime),
            const SizedBox(height: 14),
            ...fields,
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('start_submit'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPink,
                minimumSize: const Size.fromHeight(50),
                textStyle: AppTextStyles.choiceButton,
              ),
              onPressed: _submit,
              child: Text(_free ? '자유대화 시작하기' : '스토리 시작하기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 처음 시작할 때 스토리/자유대화 고르는 카드
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.note,
    required this.on,
    required this.onTap,
    this.chips = const [],
  });

  final IconData icon;
  final String title;
  final String note;
  final List<String> chips;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? Color.lerp(AppColors.surfaceWhite, AppColors.primaryPink, 0.06) : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? AppColors.primaryPink : AppColors.borderLight, width: on ? 2 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Color.lerp(AppColors.surfaceWhite, AppColors.primaryPink, on ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: on ? AppColors.primaryPink : AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.choiceButton.copyWith(color: AppColors.textPrimary, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(note, style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final c in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: Color.lerp(AppColors.surfaceWhite, AppColors.primaryPink, 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(c,
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
