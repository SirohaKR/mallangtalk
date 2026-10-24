import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/mallang_mark.dart';
import '../chat/chat_notifier.dart';
import '../library/character_library.dart';

/// [초보자 노트] 앱 하단 탭 4개: 말랑(내 캐릭터) / 채팅 / 말랑이 찾기(캐릭터 추가) / 설정
/// 탭을 옮겨도 각 탭 화면 상태(스크롤, 입력 중인 내용)가 그대로 남도록 StatefulShellRoute를 씁니다.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(chatRoomsProvider);
    var unread = 0;
    for (final id in rooms) {
      unread += ref.watch(chatRoomProvider(id).select((s) => s.unreadCount));
    }

    return Scaffold(
      body: shell,
      // 모든 탭 아이콘이 말랑 탭과 같은 색: 기본은 진한 갈색, 선택하면 분홍
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? AppColors.primaryPink : AppColors.navIcon,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          backgroundColor: AppColors.surfaceWhite,
          indicatorColor: AppColors.myBubble,
          labelTextStyle: WidgetStateProperty.all(
            AppTextStyles.messageTime.copyWith(color: AppColors.textPrimary, fontSize: 12),
          ),
          onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
          destinations: [
            const NavigationDestination(
              icon: MallangMark(),
              label: '말랑',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_rounded),
              ),
              label: '채팅',
            ),
            const NavigationDestination(
              icon: MallangMark(plus: true),
              label: '말랑이 찾기',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
