import 'package:flutter/material.dart';

/// [초보자 노트] 여백(Padding), 간격(Gap), 모서리 둥글기(Radius), 반응형 화면 폭 기준을 모아둔 파일입니다.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;

  static const double bubbleRadius = 18.0;
  static const double choiceRadius = 14.0;
  static const double cardRadius = 16.0;

  static const double mobileMaxWidth = 480.0;
  static const double tabletMaxWidth = 780.0;
  static const double desktopMaxWidth = 1080.0;
  static const double studioSplitBreakpoint = 900.0;

  /// 태블릿·PC처럼 넓은 화면인지 판정
  static bool isWide(BuildContext context, [double breakpoint = 720.0]) =>
      MediaQuery.sizeOf(context).width >= breakpoint;

  /// 모바일(<600px)에서는 기존 모바일 폭(480px)을 유지하고,
  /// 태블릿·PC에서는 화면 여백이 과도하게 남지 않도록 자연스럽게 넓힌 폭 제약
  static BoxConstraints pageConstraints(
    BuildContext context, {
    double maxDesktop = desktopMaxWidth,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return const BoxConstraints(maxWidth: mobileMaxWidth);
    return BoxConstraints(maxWidth: (w - 48).clamp(mobileMaxWidth, maxDesktop));
  }

  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(
    horizontal: 14.0,
    vertical: 10.0,
  );

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
}
