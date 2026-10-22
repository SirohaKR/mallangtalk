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
/// 처음 대화하는 캐릭터면 먼저 '이 대화에서 쓸 내 별명'을 묻고(설정의 기본 별명이 미리 들어감), 정한 뒤에 대화가 시작됩니다.
/// 상태는 [context]가 속한 ProviderScope에서 직접 읽어요. 프로필 시트처럼 먼저 닫히는 화면의 ref를 쓰면
/// 시트가 닫히는 순간 ref가 사라져서 대화방으로 넘어가지 못하거든요.
Future<void> openChat(BuildContext context, CharacterModel character) async {
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = container.read(chatPrefsProvider(character.id));
  if (prefs.nickname == null) {
    final nickname = await askChatNickname(context, character, isFirstTime: true);
    if (nickname == null) return;
  }
  container.read(chatRoomsProvider.notifier).open(character.id);
  container.read(chatRoomProvider(character.id).notifier).begin();
  router.push('/chat/${character.id}');
}

/// 이 캐릭터와의 대화에서 불릴 내 별명을 묻고 저장합니다. 취소하면 null
Future<String?> askChatNickname(
  BuildContext context,
  CharacterModel character, {
  bool isFirstTime = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final current = container.read(chatPrefsProvider(character.id)).nickname ??
      container.read(userProfileProvider).nickname;
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _NicknameDialog(character: character, initial: current, isFirstTime: isFirstTime),
  );
  if (result == null) return null;
  await container.read(chatPrefsProvider(character.id).notifier).setNickname(result);
  return result;
}

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

/// 별명 입력 창. 입력칸 컨트롤러를 창이 직접 들고 있다가 닫히는 애니메이션이 끝난 뒤 정리합니다.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.character, required this.initial, required this.isFirstTime});

  final CharacterModel character;
  final String initial;
  final bool isFirstTime;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return setState(() => _error = '별명을 적어 주세요');
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.character.name;
    return AlertDialog(
      title: Text(widget.isFirstTime ? '${josa(name, '과', '와')} 대화 시작' : '이 대화에서 내 별명'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${josa(name, '이', '가')} 나를 이렇게 불러요. 설정의 기본 별명이 들어가 있고, 이 대화에서만 바꿀 수 있어요.',
            style: AppTextStyles.systemNotice,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 12,
            decoration: InputDecoration(hintText: '내 별명', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
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
