import 'package:flutter/material.dart';
import 'app_colors.dart';

/// [초보자 노트] 앱에서 사용하는 모든 글씨 크기와 굵기(Typography)를 모아둔 파일입니다.
class AppTextStyles {
  AppTextStyles._();

  /// 앱에 내장한 한국어 글꼴 (AppBar·버튼처럼 테마 글꼴을 안 물려받는 곳에서도 한글이 깨지지 않게)
  static const String fontFamily = 'NotoSansKR';

  static const TextStyle appBarTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle speakerName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.2,
  );

  static const TextStyle chatBubbleBody = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle unreadCount = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: AppColors.unreadBadgeYellow,
    height: 1.0,
  );

  static const TextStyle messageTime = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.0,
  );

  static const TextStyle choiceButton = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.primaryNavy,
    height: 1.35,
  );

  static const TextStyle systemNotice = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.3,
  );
}
