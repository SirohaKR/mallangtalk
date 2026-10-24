import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'mallang_mark.dart';

/// [초보자 노트] AI가 캐릭터·대사를 만드는 동안 화면 전체를 덮는 로딩 화면입니다.
/// 화면을 회색으로 어둡게 깔고(뒤쪽은 눌리지 않음), 가운데에서 말랑이가 통통 튀어요.
/// 말랑이 머리 위 말풍선에 지금 하는 일([message])과 몇 퍼센트인지([progress])를 보여 줘요.
/// progress가 null이면 퍼센트 없이 '…' 만 움직여요 (단계를 셀 수 없는 일).
class MallangLoadingOverlay extends StatefulWidget {
  const MallangLoadingOverlay({super.key, required this.message, this.progress});

  final String message;

  /// 0~1. 비우면 퍼센트를 숨겨요.
  final double? progress;

  @override
  State<MallangLoadingOverlay> createState() => _MallangLoadingOverlayState();
}

class _MallangLoadingOverlayState extends State<MallangLoadingOverlay> with SingleTickerProviderStateMixin {
  // 한 번 뛰었다 내려오는 데 0.9초
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress?.clamp(0.0, 1.0);
    return Semantics(
      liveRegion: true,
      label: progress == null ? widget.message : '${widget.message} ${(progress * 100).round()}%',
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: AbsorbPointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bubble(message: widget.message, progress: progress, ticker: _bounce),
                const SizedBox(height: 18),
                AnimatedBuilder(animation: _bounce, builder: (_, __) => _bouncingMallang(_bounce.value)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// t(0~1)에 따라 말랑이 높이·찌그러짐·그림자를 정해요.
  Widget _bouncingMallang(double t) {
    const size = 120.0;
    const jump = 46.0;
    // 공중에 뜬 정도 0(바닥)~1(꼭대기). 포물선처럼 바닥에서 빠르고 위에서 느리게
    final height = math.sin(math.pi * t);
    // 바닥에 닿는 순간(t가 0·1 근처)에 납작하게, 뜰 때는 살짝 길쭉하게
    final ground = math.pow(1 - height, 6).toDouble();
    final scaleX = 1 + 0.16 * ground - 0.04 * height;
    final scaleY = 1 - 0.18 * ground + 0.05 * height;
    return SizedBox(
      width: size * 1.4,
      height: size + jump + 14,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // 바닥 그림자: 높이 뜰수록 작고 옅게
          Positioned(
            bottom: 0,
            child: Container(
              width: size * (0.8 - 0.3 * height),
              height: 12 * (1 - 0.3 * height),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28 - 0.14 * height),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 5 + jump * height,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: const MallangMark(size: size, color: Colors.white, eyeColor: Color(0xFF5B3F46)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.progress, required this.ticker});

  final String message;
  final double? progress;
  final Animation<double> ticker;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p != null)
                  // 퍼센트가 툭툭 튀지 않고 부드럽게 올라가게
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: p),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => Column(
                      children: [
                        Text(
                          '${(v * 100).round()}%',
                          style: AppTextStyles.choiceButton.copyWith(fontSize: 22, color: AppColors.primaryPink),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: v,
                            minHeight: 6,
                            color: AppColors.primaryPink,
                            backgroundColor: AppColors.primaryPink.withValues(alpha: 0.15),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.choiceButton.copyWith(fontSize: 14, height: 1.4),
                ),
                if (p == null) ...[
                  const SizedBox(height: 6),
                  _Dots(ticker: ticker),
                ],
              ],
            ),
          ),
          // 말풍선 꼬리 (아래쪽 말랑이를 가리킴)
          CustomPaint(size: const Size(20, 10), painter: _TailPainter()),
        ],
      ),
    );
  }
}

/// 퍼센트를 모를 때 보이는 점 세 개 (차례로 커졌다 작아짐)
class _Dots extends StatelessWidget {
  const _Dots({required this.ticker});

  final Animation<double> ticker;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ticker,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: 0.3 + 0.7 * math.max(0, math.sin(math.pi * 2 * (ticker.value - i / 3))),
                child: const CircleAvatar(radius: 3.5, backgroundColor: AppColors.primaryPink),
              ),
            ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}
