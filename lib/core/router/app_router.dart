import 'package:go_router/go_router.dart';
import '../../features/album/album_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/settings/settings_screen.dart';

/// [초보자 노트] GoRouter로 화면 주소를 정해 둔 파일입니다.
/// 채팅방(/)에서 앨범(/album), 설정(/settings)으로 이동하고 뒤로가기로 돌아옵니다.
final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ChatScreen(),
      routes: [
        GoRoute(path: 'album', builder: (context, state) => const AlbumScreen()),
        GoRoute(path: 'settings', builder: (context, state) => const SettingsScreen()),
      ],
    ),
  ],
);
