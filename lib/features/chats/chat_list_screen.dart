import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../chat/chat_notifier.dart';
import '../chat/start_chat.dart';
import '../library/character_library.dart';

/// [초보자 노트] '채팅' 탭: 대화 중인 캐릭터 목록. 마지막 말풍선과 안 읽은 톡 숫자를 카톡처럼 보여줍니다.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(chatRoomsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('채팅')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: rooms.isEmpty
              ? Padding(
                  padding: AppSpacing.screenPadding,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.textMuted),
                      const SizedBox(height: AppSpacing.md),
                      const Text('아직 대화방이 없어요', style: AppTextStyles.appBarTitle),
                      const SizedBox(height: 6),
                      const Text('친구 탭에서 프로필을 누르고 1:1 채팅을 시작해 보세요',
                          textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: () => context.go('/my'),
                        child: const Text('친구 보기'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) => _ChatRoomTile(characterId: rooms[index]),
                ),
        ),
      ),
    );
  }
}

class _ChatRoomTile extends ConsumerWidget {
  const _ChatRoomTile({required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(chatRoomProvider(characterId));
    final last = room.lastBubble;
    final unread = room.unreadCount;
    final preview = room.isCharacterTyping
        ? '입력 중...'
        : last == null
            ? '대화를 시작해 보세요'
            : last.hasPhoto && last.text.isEmpty
                ? '사진'
                : last.text;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
      leading: CharacterAvatar(character: room.character, radius: 24),
      title: Text(room.character.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.systemNotice.copyWith(
          color: room.isCharacterTyping ? AppColors.aiActivePurple : AppColors.textSecondary,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null) Text(_timeLabel(last.timestamp), style: AppTextStyles.messageTime),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryPink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread',
                style: AppTextStyles.messageTime.copyWith(
                  color: AppColors.surfaceWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onTap: () => openChat(context, room.character),
    );
  }

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    if (now.year == t.year && now.month == t.month && now.day == t.day) {
      final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '${t.hour < 12 ? '오전' : '오후'} $hour:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}월 ${t.day}일';
  }
}
