import 'package:flutter/material.dart';

/// [초보자 노트] 앱 전체에서 사용하는 색상표(Color Palette)입니다.
/// 코드 곳곳에 Color(0xFFFFF0F5)처럼 숫자를 직접 쓰면 나중에 색을 바꿀 때 일일이 찾아야 하지만,
/// 이렇게 AppColors.chatRoomBackground처럼 이름표를 붙여두면 이 파일 하나만 수정해도 앱 전체 색상이 바뀝니다!
/// (참고 구조: https://github.com/SirohaKR/taskflow_example 의 lib/core/theme 분리 방식)
class AppColors {
  AppColors._();

  // ==========================================================
  // 1. 카톡/메신저 배경 및 기본 표면 색상 (파스텔 핑크 테마 기본값)
  // ==========================================================
  static const Color scaffoldBackground = Color(0xFFFDF8FA);
  static const Color chatRoomBackground = Color(0xFFF7EBF0);
  static const Color surfaceWhite = Color(0xFFFFFFFF);

  // ==========================================================
  // 2. 브랜드 포인트 및 관계 단계 아이콘 색상 (점수 숫자는 숨기고 색으로만 은은하게 표현)
  // ==========================================================
  static const Color primaryPink = Color(0xFFE86A92);
  static const Color primaryNavy = Color(0xFF2B3A55);
  static const Color aiActivePurple = Color(0xFF7C5CBF);

  // 온더훅 스타일 단계별 아이콘 색상 (어색함 -> 친구 -> 썸/연인)
  static const Color affectionCold = Color(0xFF7CA1C4); // 0~29: 파란빛
  static const Color affectionWarm = Color(0xFFF4A261); // 30~69: 살구빛
  static const Color affectionLove = Color(0xFFE86A92); // 70~100: 분홍빛

  // ==========================================================
  // 3. 채팅 말풍선 & 읽음 표시(1) 색상
  // ==========================================================
  static const Color partnerBubble = Color(0xFFFFFFFF);
  static const Color myBubble = Color(0xFFFFE0EB);
  static const Color intrusionBubble = Color(0xFFEEF2FF);
  static const Color unreadBadgeYellow = Color(0xFFFFB703);

  // ==========================================================
  // 4. 텍스트 및 테두리(Border) 색상
  // ==========================================================
  static const Color textPrimary = Color(0xFF1E2430);
  static const Color textSecondary = Color(0xFF687082);
  static const Color textMuted = Color(0xFF9AA1B2);
  static const Color borderLight = Color(0xFFE6E1E6);
}
