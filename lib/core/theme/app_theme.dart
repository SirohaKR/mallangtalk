import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// [초보자 노트] AppColors, AppTextStyles, AppSpacing을 합쳐 MaterialApp에 주입하는 테마 설정 파일입니다.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTextStyles.fontFamily, // 앱에 같이 넣은 한국어 글꼴 (외부 글꼴 서버 없이도 한글이 바로 보임)
      scaffoldBackgroundColor: AppColors.scaffoldBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryPink,
        primary: AppColors.primaryPink,
        secondary: AppColors.primaryNavy,
        surface: AppColors.surfaceWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceWhite,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.appBarTitle,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceWhite,
          foregroundColor: AppColors.primaryNavy,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
            side: const BorderSide(color: AppColors.borderLight, width: 1.2),
          ),
          textStyle: AppTextStyles.choiceButton,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
          borderSide: const BorderSide(color: AppColors.primaryPink, width: 1.5),
        ),
      ),
    );
  }
}
