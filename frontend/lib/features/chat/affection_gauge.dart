import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/mallang_mark.dart';

/// [초보자 노트] 대화 중 캐릭터 프로필에 보이는 호감도.
/// 숫자는 보여 주지 않고, 말랑이가 아래에서부터 대표색으로 차오르는 모습과 지금 단계 이름만 보여 줘요.
/// 아직 닿지 않은 단계 이름은 '?'로 가려 둡니다.
class AffectionGauge extends StatelessWidget {
  const AffectionGauge({super.key, required this.character, required this.affection, required this.accent});

  final CharacterModel character;
  final int affection;
  final Color accent;

  /// 말랑이가 얼마나 찼는지 (0~1). 단계 수로 나눠서 단계 안에서도 조금씩 참
  static double fillOf(CharacterModel c, int affection) {
    final stages = c.affectionStages;
    final current = c.stageFor(affection);
    if (stages.isEmpty || current == null) return 0;
    final index = stages.indexOf(current);
    final span = (current.maxScore - current.minScore + 1).clamp(1, 1 << 30);
    final inside = ((affection - current.minScore) / span).clamp(0.0, 1.0);
    return ((index + inside) / stages.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final stages = character.affectionStages;
    final current = character.stageFor(affection);
    if (stages.isEmpty || current == null) return const SizedBox.shrink();
    final index = stages.indexOf(current);
    final fill = fillOf(character, affection);
    return Container(
      key: const ValueKey('affection_gauge'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.surfaceWhite, accent, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _FillingMallang(fill: fill, accent: accent, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('지금 우리 사이', style: AppTextStyles.messageTime),
                    const SizedBox(height: 2),
                    Text(current.stageLabel, style: AppTextStyles.appBarTitle.copyWith(fontSize: 17)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < stages.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: i <= index ? accent : Color.lerp(AppColors.borderLight, accent, 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (var i = 0; i < stages.length; i++)
                          Expanded(
                            child: Text(
                              i <= index ? stages[i].stageLabel : '?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: i == 0
                                  ? TextAlign.start
                                  : i == stages.length - 1
                                      ? TextAlign.end
                                      : TextAlign.center,
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('말랑이는 대화할수록 차올라요. 다음 단계 이름은 도달하면 보여요.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 연한 말랑이 위에 진한 말랑이를 아래에서부터 [fill]만큼 겹쳐 그림
class _FillingMallang extends StatelessWidget {
  const _FillingMallang({required this.fill, required this.accent, required this.size});

  final double fill;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          MallangMark(
              size: size,
              color: Color.lerp(AppColors.surfaceWhite, accent, 0.22),
              eyeColor: accent.withValues(alpha: 0.55)),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: fill,
              child: MallangMark(size: size, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
