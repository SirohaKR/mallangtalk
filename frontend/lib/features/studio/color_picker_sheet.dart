import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// '#RRGGBB' → Color. 형식이 틀리면 null
Color? colorFromHex(String hex) {
  final s = hex.replaceAll('#', '').trim();
  final v = int.tryParse(s, radix: 16);
  if (s.length != 6 || v == null) return null;
  return Color(0xFF000000 | v);
}

/// Color → '#RRGGBB' (대문자)
String hexFromColor(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 무지개 버튼을 누르면 뜨는 색 고르기 창.
/// 큰 네모(진하기·밝기)와 무지개 막대(색깔)를 끌어서 고르고, 고른 색을 '#RRGGBB'로 돌려줌. 취소하면 null
Future<String?> showColorPickerSheet(BuildContext context, {String initial = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ColorPickerBody(initial: colorFromHex(initial) ?? AppColors.primaryPink),
  );
}

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends State<_ColorPickerBody> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(child: Text('색 고르기', style: AppTextStyles.speakerName)),
              Container(
                key: const ValueKey('color_picker_swatch'),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.borderLight),
                ),
              ),
              const SizedBox(width: 8),
              Text(hexFromColor(_color), key: const ValueKey('color_picker_hex'), style: AppTextStyles.messageTime),
            ]),
            const SizedBox(height: AppSpacing.md),
            // 진하기(가로) · 밝기(세로)
            AspectRatio(
              aspectRatio: 1.6,
              child: LayoutBuilder(builder: (context, box) {
                void pick(Offset p) => setState(() {
                      _hsv = _hsv
                          .withSaturation((p.dx / box.maxWidth).clamp(0.0, 1.0))
                          .withValue(1 - (p.dy / box.maxHeight).clamp(0.0, 1.0));
                    });
                return GestureDetector(
                  key: const ValueKey('color_picker_area'),
                  onPanDown: (e) => pick(e.localPosition),
                  onPanUpdate: (e) => pick(e.localPosition),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.white,
                              HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                            ]),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: _hsv.saturation * box.maxWidth - 11,
                        top: (1 - _hsv.value) * box.maxHeight - 11,
                        child: _Knob(color: _color),
                      ),
                    ]),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            // 무지개 막대(색깔)
            SizedBox(
              height: 28,
              child: LayoutBuilder(builder: (context, box) {
                void pick(Offset p) => setState(() {
                      _hsv = _hsv.withHue((p.dx / box.maxWidth).clamp(0.0, 1.0) * 359.9);
                    });
                return GestureDetector(
                  key: const ValueKey('color_picker_hue'),
                  onPanDown: (e) => pick(e.localPosition),
                  onPanUpdate: (e) => pick(e.localPosition),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      top: 4,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(colors: [
                            for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor(),
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      left: _hsv.hue / 360 * box.maxWidth - 11,
                      top: 3,
                      child: _Knob(color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor()),
                    ),
                  ]),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('color_picker_done'),
                  style: FilledButton.styleFrom(backgroundColor: _color),
                  onPressed: () => Navigator.pop(context, hexFromColor(_color)),
                  child: const Text('이 색으로'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
          ),
        ),
      );
}

/// 프리셋 옆에 놓는 무지개 동그라미 버튼. 프리셋에 없는 색을 고르면 그 색과 체크 표시를 보여 줌
class RainbowColorButton extends StatelessWidget {
  const RainbowColorButton({super.key, required this.selected, required this.onTap});

  /// 프리셋이 아닌 직접 고른 색 (없으면 null)
  final Color? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [
              Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
              Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
            ]),
          ),
          child: selected == null
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: selected,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                ),
        ),
      );
}
