import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_screen.dart';
import '../chat/start_chat.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';

/// [초보자 노트] '채팅' 탭: 대화 중인 캐릭터 목록. 마지막 말풍선과 안 읽은 톡 숫자를 카톡처럼 보여줍니다.
/// PC 넓은 화면(>=860px)에서는 좌측에 채팅방 목록, 우측에 선택한 대화방을 나란히 띄워 여백 없이 한눈에 보여줍니다.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  String? _selectedRoomId;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(chatRoomsProvider);
    final isSplitDesktop = MediaQuery.sizeOf(context).width >= 860 && rooms.isNotEmpty;
    // 사용자가 직접 누른 방만 우측에 열어, 채팅 탭에 들어온 것만으로 안 읽음 배지가 사라지지 않게 함
    final activeRoomId = rooms.contains(_selectedRoomId) ? _selectedRoomId : null;

    return Scaffold(
      appBar: AppBar(title: const Text('채팅')),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context),
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
              : isSplitDesktop
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 360,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceWhite,
                                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                itemCount: rooms.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                                itemBuilder: (context, index) {
                                  final rId = rooms[index];
                                  return _ChatRoomTile(
                                    roomId: rId,
                                    selected: rId == activeRoomId,
                                    onSelectInSplit: () {
                                      final charId = characterIdOfRoom(rId);
                                      final room = ref.read(chatRoomProvider(rId));
                                      if (ref.read(chatPrefsProvider(charId)).nickname == null) {
                                        openChat(context, room.character, roomId: rId);
                                        return;
                                      }
                                      if (!isFreeRoom(rId)) {
                                        ref.read(chatRoomProvider(rId).notifier).begin();
                                      }
                                      setState(() => _selectedRoomId = rId);
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceWhite,
                                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: activeRoomId != null
                                  ? ChatScreen(
                                      key: ValueKey('split_$activeRoomId'),
                                      roomId: activeRoomId,
                                      embedded: true,
                                      onSwitchRoom: (nextRoom) => setState(() => _selectedRoomId = nextRoom),
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AppColors.textMuted),
                                          SizedBox(height: AppSpacing.sm),
                                          Text('왼쪽 목록에서 대화방을 선택해 대화를 이어가 보세요',
                                              style: AppTextStyles.systemNotice),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: rooms.length,
                      itemBuilder: (context, index) => _ChatRoomTile(roomId: rooms[index]),
                    ),
        ),
      ),
    );
  }
}

class _ChatRoomTile extends ConsumerWidget {
  const _ChatRoomTile({
    required this.roomId,
    this.selected = false,
    this.onSelectInSplit,
  });

  /// 스토리 방은 캐릭터 ID, 자유대화 방은 ID#free
  final String roomId;
  final bool selected;
  final VoidCallback? onSelectInSplit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(chatRoomProvider(roomId));
    final free = isFreeRoom(roomId);
    final service = room.character.isService;
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
      selected: selected,
      selectedTileColor: AppColors.myBubble.withValues(alpha: 0.45),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
      leading: CharacterAvatar(character: room.character, radius: 24),
      title: Row(
        children: [
          Flexible(
            child: Text(room.character.name,
                overflow: TextOverflow.ellipsis, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
          ),
          const SizedBox(width: 6),
          // 어느 방인지 (스토리/자유대화)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: service
                  ? const Color(0xFFFCEFD2)
                  : free
                      ? const Color(0xFFEDE7FB)
                      : const Color(0xFFFCE8EF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              service
                  ? '서비스'
                  : free
                      ? '자유대화'
                      : '스토리',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: service
                    ? const Color(0xFF6B4800)
                    : free
                        ? AppColors.aiActivePurple
                        : AppColors.primaryPink,
              ),
            ),
          ),
        ],
      ),
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
      onTap: onSelectInSplit ?? () => openChat(context, room.character, roomId: roomId),
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
