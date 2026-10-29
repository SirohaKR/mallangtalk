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
  const CharacterSheetView({super.key, required this.character, this.nickname = '너', this.sections = SheetSection.values});

  final CharacterModel character;
  final String nickname;

  /// 보여 줄 묶음 (상세 화면은 탭마다 일부만)
  final List<SheetSection> sections;

  /// 이 묶음에 보여 줄 내용이 있는지 (빈 탭을 숨기려고)
  static bool hasContent(CharacterModel c, SheetSection section) => switch (section) {
        SheetSection.info => c.profileFields.any((f) => !f.isSecret && f.value.trim().isNotEmpty),
        SheetSection.setting => c.worldviewPrompt.trim().isNotEmpty,
        SheetSection.world => c.worldSetting.trim().isNotEmpty,
        SheetSection.role => c.userRole.trim().isNotEmpty,
        SheetSection.cast => c.extraCast.isNotEmpty,
        SheetSection.comment => c.authorComment.trim().isNotEmpty,
      };

  @override
  Widget build(BuildContext context) {
    final c = character;
    final fields = c.profileFields.where((f) => !f.isSecret && f.value.trim().isNotEmpty).toList();
    String fill(String text) => CharacterModel.fillUserName(text, nickname, charName: character.name);
    Widget body(String text) => Text(fill(text.trim()), style: AppTextStyles.chatBubbleBody);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isNotEmpty && sections.contains(SheetSection.info))
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
        if (c.worldviewPrompt.trim().isNotEmpty && sections.contains(SheetSection.setting)) _Card(title: '캐릭터 설정', child: body(c.worldviewPrompt)),
        if (c.worldSetting.trim().isNotEmpty && sections.contains(SheetSection.world)) _Card(title: '세계관 설정', child: body(c.worldSetting)),
        if (c.userRole.trim().isNotEmpty && sections.contains(SheetSection.role)) _Card(title: '나는 이 이야기에서', child: body(c.userRole)),
        if (c.extraCast.isNotEmpty && sections.contains(SheetSection.cast))
          _Card(
            title: '주변 인물',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in c.extraCast)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(TextSpan(children: [
                      if (e.characterId != null)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.link_rounded, size: 15, color: AppColors.primaryPink),
                          ),
                        ),
                      TextSpan(text: e.name, style: AppTextStyles.speakerName.copyWith(color: AppColors.textPrimary)),
                      if (e.role.isNotEmpty) TextSpan(text: '  ${fill(e.role)}', style: AppTextStyles.systemNotice),
                    ])),
                  ),
              ],
            ),
          ),
        if (c.authorComment.trim().isNotEmpty && sections.contains(SheetSection.comment)) _Card(title: '작가 코멘트', child: body(c.authorComment)),
      ],
    );
  }
}

/// 캐릭터 설정 카드 묶음 하나
enum SheetSection { info, setting, world, role, cast, comment }

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
