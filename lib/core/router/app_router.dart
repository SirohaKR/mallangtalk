import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/add/add_character_screen.dart';
import '../../features/album/album_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chats/chat_list_screen.dart';
import '../../features/home/friends_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/settings/settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// [초보자 노트] GoRouter로 화면 주소를 정해 둔 파일입니다.
/// - 하단 탭 4개: /friends(내 캐릭터) /chats(채팅) /add(캐릭터 추가) /settings(설정)
/// - 대화방은 탭 위에 전체 화면으로: /chat/캐릭터ID, 앨범은 /chat/캐릭터ID/album
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/friends',
  redirect: (context, state) => state.uri.path == '/' ? '/friends' : null,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/friends', builder: (context, state) => const FriendsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/chats', builder: (context, state) => const ChatListScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/add', builder: (context, state) => const AddCharacterScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ]),
      ],
    ),
    GoRoute(
      path: '/chat/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ChatRoomPage(characterId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'album',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => AlbumScreen(characterId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
