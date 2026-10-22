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

/// [초보자 노트] 캐릭터 설정 카드 묶음 (loreshelf 캐릭터 아카이브 참고).
/// 대표 대사 · 프로필 항목 · 성격 막대 · 대사 예시 · 유저 설정 · 주변 인물을 보여줍니다.
/// 비밀 항목과 비밀 설정은 플레이어에게 안 보이고 AI와 대본만 알고 있어요.
class CharacterSheetView extends StatelessWidget {
  const CharacterSheetView({super.key, required this.character, this.nickname = '너'});

  final CharacterModel character;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    final c = character;
    final accent = characterThemeColor(c);
    final fields = c.profileFields.where((f) => !f.isSecret && f.value.trim().isNotEmpty).toList();
    final hiddenCount = c.profileFields.where((f) => f.isSecret).length + (c.secret.isNotEmpty ? 1 : 0);
    String fill(String text) => CharacterModel.fillUserName(text, nickname);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.quote.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border(left: BorderSide(color: accent, width: 3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('“${fill(c.quote)}”', style: AppTextStyles.chatBubbleBody.copyWith(fontStyle: FontStyle.italic)),
          ),
        if (fields.isNotEmpty)
          _Card(
            title: '프로필',
            child: Column(
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 72, child: Text(f.label, style: AppTextStyles.systemNotice)),
                        Expanded(child: Text(fill(f.value), style: AppTextStyles.chatBubbleBody)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (c.traits.isNotEmpty)
          _Card(
            title: '성격',
            child: Column(children: [for (final t in c.traits) _TraitBar(trait: t, color: accent)]),
          ),
        if (c.sampleQuotes.isNotEmpty)
          _Card(
            title: '대사',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final q in c.sampleQuotes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (q.situation.isNotEmpty) Text(fill(q.situation), style: AppTextStyles.messageTime),
                        Text('“${fill(q.body)}”', style: AppTextStyles.chatBubbleBody),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (c.userRole.isNotEmpty)
          _Card(title: '나는 이 이야기에서', child: Text(fill(c.userRole), style: AppTextStyles.chatBubbleBody)),
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
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('아직 모르는 비밀 $hiddenCount개', style: AppTextStyles.systemNotice),
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

class _TraitBar extends StatelessWidget {
  const _TraitBar({required this.trait, required this.color});

  final PersonalityTrait trait;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final twoSided = trait.right != null && trait.right!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(trait.left, style: AppTextStyles.systemNotice),
              const Spacer(),
              Text(twoSided ? trait.right! : '${trait.percent}%', style: AppTextStyles.systemNotice),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: trait.percent / 100,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
