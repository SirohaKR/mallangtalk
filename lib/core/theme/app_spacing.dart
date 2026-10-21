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
  static const double studioSplitBreakpoint = 900.0;

  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(
    horizontal: 14.0,
    vertical: 10.0,
  );

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
}
