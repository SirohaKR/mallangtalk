import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/mallangtalk_models.dart';

/// 캐릭터 대표 색 (#RRGGBB). 비었거나 잘못 쓰면 기본 분홍
Color characterThemeColor(CharacterModel c) {
  final hex = c.themeColor.replaceAll('#', '').trim();
  final value = int.tryParse(hex, radix: 16);
  if (hex.length != 6 || value == null) return AppColors.primaryPink;
  return Color(0xFF000000 | value);
}

/// [초보자 노트] 플레이어에게 보이는 캐릭터 설정 카드 묶음 (loreshelf 캐릭터 아카이브 참고).
/// 캐릭터 정보 · 캐릭터 설정 · 세계관 설정 · 나는 이 이야기에서 · 주변 인물만 보여 줍니다.
/// 호감도 단계, 성격 막대, 대사 예시, 비밀처럼 제작자·AI만 쓰는 내용은 만들기 화면에만 있어요.
class CharacterSheetView extends StatelessWidget {
  const CharacterSheetView({super.key, required this.character, this.nickname = '너'});

  final CharacterModel character;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    final c = character;
    final fields = c.profileFields.where((f) => !f.isSecret && f.value.trim().isNotEmpty).toList();
    String fill(String text) => CharacterModel.fillUserName(text, nickname, charName: character.name);
    Widget body(String text) => Text(fill(text.trim()), style: AppTextStyles.chatBubbleBody);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isNotEmpty)
          _Card(
            title: '캐릭터 정보',
            child: Column(
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 80, child: Text(f.label, style: AppTextStyles.systemNotice)),
                        Expanded(child: body(f.value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (c.worldviewPrompt.trim().isNotEmpty) _Card(title: '캐릭터 설정', child: body(c.worldviewPrompt)),
        if (c.worldSetting.trim().isNotEmpty) _Card(title: '세계관 설정', child: body(c.worldSetting)),
        if (c.userRole.trim().isNotEmpty) _Card(title: '나는 이 이야기에서', child: body(c.userRole)),
        if (c.extraCast.isNotEmpty)
          _Card(
            title: '주변 인물',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in c.extraCast)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: e.name, style: AppTextStyles.speakerName.copyWith(color: AppColors.textPrimary)),
                      if (e.role.isNotEmpty) TextSpan(text: '  ${fill(e.role)}', style: AppTextStyles.systemNotice),
                    ])),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTextStyles.speakerName),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
