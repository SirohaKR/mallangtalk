import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/server_info.dart';
import 'core/router/app_router.dart';
import 'core/storage/local_store.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/state_sync.dart';
import 'features/library/character_library.dart';

class MallangTalkApp extends StatelessWidget {
  const MallangTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MallangTalk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      builder: (context, child) => _BootGate(child: child!),
    );
  }
}

/// [초보자 노트] 기본 캐릭터 파일과 브라우저 저장소를 다 불러올 때까지 로딩 화면을 보여주는 문지기입니다.
/// 덕분에 어느 화면에서 새로고침해도 데이터가 준비된 뒤에 화면이 그려지고,
/// 다른 기기(모바일 ↔ PC)에서 돌아왔을 때 자동으로 최신 진행도를 맞춥니다.
class _BootGate extends ConsumerStatefulWidget {
  const _BootGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<_BootGate> with WidgetsBindingObserver {
  String? _syncedUsername;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // 화면을 벗어나거나 탭을 옮길 때 아직 안 보낸 변경분을 즉시 서버로 전송
      ref.read(syncOutboxProvider).flush();
    } else if (state == AppLifecycleState.resumed && _syncedUsername == auth.user?.username) {
      // 다른 기기(폰 ↔ PC)에서 진행한 뒤 이 화면으로 돌아오면 서버와 다시 동기화
      ref.invalidate(stateSyncProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(builtinBundlesProvider);
    final prefs = ref.watch(sharedPreferencesProvider);

    final error = bundle.error ?? prefs.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.chatRoomBackground,
        body: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Text(
              '앱을 불러오지 못했어요\n$error',
              textAlign: TextAlign.center,
              style: AppTextStyles.systemNotice,
            ),
          ),
        ),
      );
    }
    // 웹에서는 말랑톡 서버인지 확인할 때까지 기다림 (서버면 로그인 화면부터)
    final server = ref.watch(serverInfoProvider);
    if (!bundle.hasValue || !prefs.hasValue || (kIsWeb && server.isLoading)) {
      return const Scaffold(
        backgroundColor: AppColors.chatRoomBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final auth = ref.watch(authProvider);
    if (server.valueOrNull?.accounts ?? false) {
      if (!auth.isLoggedIn) {
        _syncedUsername = null;
        // 로그인 화면의 입력칸이 쓸 Navigator(오버레이)를 따로 둠
        return Navigator(
          pages: const [MaterialPage(child: LoginScreen())],
          onDidRemovePage: (_) {},
        );
      }
      final username = auth.user?.username;
      // 로그인하면 내 프로필·진행도·앨범을 서버와 맞춘 뒤에 화면을 띄움 (PC·폰 연동)
      final sync = ref.watch(stateSyncProvider);
      ref.watch(bootSyncProvider);
      if (sync.isLoading || sync.isRefreshing) {
        if (_syncedUsername != username) {
          return const Scaffold(
            backgroundColor: AppColors.chatRoomBackground,
            body: Center(child: CircularProgressIndicator()),
          );
        }
      } else {
        _syncedUsername = username;
      }
      ref.watch(librarySyncProvider); // 내 캐릭터를 서버와 맞춤
    }
    return KeyedSubtree(
      key: ValueKey(auth.user?.username ?? '_guest_'),
      child: widget.child,
    );
  }
}
