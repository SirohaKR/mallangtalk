import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_sheet_view.dart';

/// [초보자 노트] 대화방 색 묶음. 캐릭터의 대표색(themeColor)으로 톡방을 꾸며요.
/// - 배경: 대표색을 아주 연하게 (제작자가 '흰색'을 고르면 흰색, '사진'이면 그 사진을 흐리게 깔고 위에 흰 막)
/// - 내 말풍선: 대표색 (제작자가 '기본 분홍'을 고르면 연분홍)
/// - 글자색: 말풍선이 어두우면 흰색, 밝으면 검은색으로 자동
/// - 선택지 테두리·보내기 버튼·윗줄도 대표색
/// 대표색이 비어 있으면 예전과 같은 분홍 톡방이에요.
class ChatTheme {
  const ChatTheme({
    required this.accent,
    required this.background,
    required this.myBubble,
    required this.myText,
    required this.choiceBorder,
    this.backgroundImage,
  });

  final Color accent;
  final Color background;
  final Color myBubble;
  final Color myText;
  final Color choiceBorder;

  /// 톡방 배경 사진 ('사진' 배경을 골랐을 때만)
  final String? backgroundImage;

  static const pink = ChatTheme(
    accent: AppColors.primaryPink,
    background: AppColors.chatRoomBackground,
    myBubble: AppColors.myBubble,
    myText: AppColors.textPrimary,
    choiceBorder: AppColors.borderLight,
  );

  factory ChatTheme.of(CharacterModel c) {
    final photo = c.chatBackground == 'photo' && c.chatBackgroundImage.isNotEmpty ? c.chatBackgroundImage : null;
    if (c.themeColor.trim().isEmpty) {
      return photo == null
          ? pink
          : ChatTheme(
              accent: pink.accent,
              background: pink.background,
              myBubble: pink.myBubble,
              myText: pink.myText,
              choiceBorder: pink.choiceBorder,
              backgroundImage: photo,
            );
    }
    final accent = characterThemeColor(c);
    final background = c.chatBackground == 'white' || c.chatBackground == 'photo'
        ? AppColors.surfaceWhite
        : Color.lerp(AppColors.surfaceWhite, accent, 0.09)!;
    final myBubble = c.bubbleStyle == 'pink' ? AppColors.myBubble : accent;
    return ChatTheme(
      accent: accent,
      background: background,
      myBubble: myBubble,
      myText: readableOn(myBubble),
      choiceBorder: Color.lerp(AppColors.borderLight, accent, 0.55)!,
      backgroundImage: photo,
    );
  }

  /// 이 색 위에서 잘 보이는 글자색 (흰색 또는 검은색)
  static Color readableOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? AppColors.surfaceWhite
          : AppColors.textPrimary;
}
