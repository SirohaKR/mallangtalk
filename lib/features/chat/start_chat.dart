import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import 'chat_notifier.dart';
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
  final current = container.read(chatPrefsProvider(character.id)).nickname ??
      container.read(userProfileProvider).nickname;
  final result = await showDialog<_ChatProfile>(
    context: context,
    builder: (_) => _NicknameDialog(
      character: character,
      initial: current,
      initialPersona: container.read(chatPersonaProvider(character.id)),
      isFirstTime: isFirstTime,
    ),
  );
  if (result == null) return null;
  final prefs = container.read(chatPrefsProvider(character.id).notifier);
  await prefs.setNickname(result.nickname);
  await prefs.setPersona(result.persona);
  if (result.saveAsDefault) await container.read(userProfileProvider.notifier).savePersona(result.persona);
  return result;
}

typedef _ChatProfile = ({String nickname, String persona, bool saveAsDefault, bool free});

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
                      tempo == option.tempo
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
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
    required this.isFirstTime,
  });

  final CharacterModel character;
  final String initial;
  final String initialPersona;
  final bool isFirstTime;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  late final _persona = TextEditingController(text: widget.initialPersona);
  bool _saveAsDefault = false;
  bool _free = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _persona.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return setState(() => _error = '별명을 적어 주세요');
    Navigator.pop<_ChatProfile>(context, (nickname: text, persona: _persona.text.trim(), saveAsDefault: _saveAsDefault, free: _free));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.character.name;
    return AlertDialog(
      title: Text(widget.isFirstTime ? '${josa(name, '과', '와')} 대화 시작' : '이 대화에서 나'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isFirstTime) ...[
              IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ModeCard(
                      key: const ValueKey('start_mode_story'),
                      icon: Icons.auto_stories_rounded,
                      title: '스토리',
                      note: '선택지로 가까워지고 사진을 모아요',
                      on: !_free,
                      onTap: () => setState(() => _free = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      key: const ValueKey('start_mode_free'),
                      icon: Icons.forum_rounded,
                      title: '자유대화',
                      note: '이야기 없이 AI와 마음대로 톡해요',
                      on: _free,
                      onTap: () => setState(() => _free = true),
                    ),
                  ),
                ],
              ),
              ),
              const SizedBox(height: 6),
              const Text('두 대화방은 따로 이어지고, 대화방 메뉴에서 다른 방도 열 수 있어요',
                  style: AppTextStyles.messageTime),
              const SizedBox(height: 14),
            ],
            Text(
              '${josa(name, '이', '가')} 나를 이렇게 불러요. 설정의 기본 별명이 들어가 있고, 이 대화에서만 바꿀 수 있어요.',
              style: AppTextStyles.systemNotice,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 12,
              decoration: InputDecoration(labelText: '내 별명', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('persona_field'),
              controller: _persona,
              minLines: 3,
              maxLines: 6,
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
        ),
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
  });

  final IconData icon;
  final String title;
  final String note;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: on ? Color.lerp(AppColors.surfaceWhite, AppColors.primaryPink, 0.08) : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? AppColors.primaryPink : AppColors.borderLight, width: on ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: on ? AppColors.primaryPink : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(title, style: AppTextStyles.choiceButton.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(note,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
