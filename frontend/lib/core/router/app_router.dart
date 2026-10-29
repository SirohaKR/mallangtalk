import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/add/character_detail_screen.dart';
import '../../features/album/album_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chats/chat_list_screen.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/help/welcome_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/my/my_mallang_screen.dart';
import '../../features/relations/relation_map_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/studio/studio_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// [초보자 노트] GoRouter로 화면 주소를 정해 둔 파일입니다.
/// - 하단 탭 4개: /discover(말랑이 찾기, 첫 화면) /chats(채팅) /my(내 말랑이) /settings(설정)
/// - 검색: /search, 제작자 프로필: /creator/닉네임, 갤러리 캐릭터 상세: /gallery/캐릭터ID
/// - 새 말랑이 만들기: /create, 만든 캐릭터 고치기: /edit/캐릭터ID
/// - 처음 사용자 안내(인사·프로필·AI 키): /welcome
/// - 설정 안쪽: /settings/account(계정 · 프로필), /settings/ai(AI 연결)
/// - 내가 만든 캐릭터끼리 관계도: /relations
/// - 대화방은 탭 위에 전체 화면으로: /chat/캐릭터ID(스토리), /free/캐릭터ID(자유대화), 앨범은 /chat/캐릭터ID/album
/// 옛 주소(/friends, /add)로 들어오면 새 탭으로 보내요.
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/discover',
  redirect: (context, state) => switch (state.uri.path) {
    '/' || '/add' => '/discover',
    '/friends' => '/my',
    _ => null,
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/discover',
              builder: (context, state) => const DiscoverScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/chats',
              builder: (context, state) => ChatListScreen(
                  selectedRoomId: state.uri.queryParameters['room'])),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/my',
              builder: (context, state) => const MyMallangScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen()),
        ]),
      ],
    ),
    // 처음 사용자 안내 앞부분 (인사 → 내 프로필 → AI 키)
    GoRoute(
      path: '/welcome',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/creator/:name',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          CreatorScreen(creator: state.pathParameters['name']!),
    ),
    GoRoute(
      path: '/gallery/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          CharacterDetailScreen(characterId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/settings/account',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountScreen(),
    ),
    GoRoute(
      path: '/settings/ai',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AiConnectScreen(),
    ),
    GoRoute(
      path: '/relations',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const RelationMapScreen(),
    ),
    GoRoute(
      path: '/create',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StudioScreen(),
    ),
    GoRoute(
      path: '/edit/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          EditCharacterPage(characterId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/chat/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          ChatRoomPage(characterId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'album',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) =>
              AlbumScreen(characterId: state.pathParameters['id']!),
        ),
      ],
    ),
    // 자유대화 방 (스토리 방과 따로)
    GoRoute(
      path: '/free/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          ChatRoomPage(characterId: state.pathParameters['id']!, free: true),
    ),
  ],
);
