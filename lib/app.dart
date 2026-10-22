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
/// 덕분에 어느 화면에서 새로고침해도 데이터가 준비된 뒤에 화면이 그려집니다.
class _BootGate extends ConsumerWidget {
  const _BootGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    if (server.valueOrNull?.accounts ?? false) {
      if (!ref.watch(authProvider).isLoggedIn) {
        // 로그인 화면의 입력칸이 쓸 Navigator(오버레이)를 따로 둠
        return Navigator(
          pages: const [MaterialPage(child: LoginScreen())],
          onDidRemovePage: (_) {},
        );
      }
      ref.watch(librarySyncProvider); // 로그인하면 내 캐릭터를 서버와 맞춤
    }
    return child;
  }
}
