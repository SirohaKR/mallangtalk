import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/storage/local_store.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
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
    if (!bundle.hasValue || !prefs.hasValue) {
      return const Scaffold(
        backgroundColor: AppColors.chatRoomBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return child;
  }
}
