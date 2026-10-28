import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../utils/photo_encode_stub.dart' if (dart.library.js_interop) '../utils/photo_encode_web.dart';

/// 사진 편집 화면 모양: 프로필(동그라미 1:1) 또는 일반 사진(비율 고르기)
enum PhotoCropShape { profile, photo }

/// [초보자 노트] 앱에서 흔히 보는 '사진 자르기' 화면이에요. (crop_your_image 패키지 사용)
/// - 프로필: 동그란 틀은 그대로 두고, 사진을 끌어서 옮기거나 두 손가락(PC는 마우스 휠)으로 확대·축소
/// - 일반 사진(대사 사진·컷씬): 네 모서리를 끌어서 자를 영역을 정하고, 아래에서 비율(원본·1:1·4:3…)을 골라요
/// 완료를 누르면 고른 영역만 잘라 긴 쪽 [maxSide]px로 줄인 data: 주소를 돌려줘요. 취소하면 null.
Future<String?> showPhotoCropScreen(
  BuildContext context, {
  required Uint8List bytes,
  required PhotoCropShape shape,
  required int maxSide,
}) async {
  // 큰 폰 사진도 편집 화면이 버벅이지 않게 먼저 줄여 둠
  final prepared = await preparePhoto(bytes, 1600);
  if (prepared == null || !context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoCropScreen(photo: prepared, shape: shape, maxSide: maxSide),
    ),
  );
}

class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.photo, required this.shape, required this.maxSide});

  final PreparedPhoto photo;
  final PhotoCropShape shape;
  final int maxSide;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

/// 고를 수 있는 비율 (null = 자유)
typedef _Ratio = ({String label, double? value});

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _controller = CropController();
  late final List<_Ratio> _ratios = [
    (label: '원본', value: widget.photo.width / widget.photo.height),
    (label: '자유', value: null),
    (label: '1:1', value: 1),
    (label: '4:3', value: 4 / 3),
    (label: '3:4', value: 3 / 4),
    (label: '16:9', value: 16 / 9),
  ];
  int _ratioIndex = 0;
  bool _ready = false;
  bool _saving = false;
  Rect? _cropRect; // 화면 기준 자르기 틀
  Rect? _imageRect; // 화면 기준 사진 위치·크기

  bool get _isProfile => widget.shape == PhotoCropShape.profile;

  /// 화면 기준 틀 → 사진 기준 영역 (사진 밖은 잘라냄)
  Rect? get _area {
    final crop = _cropRect, image = _imageRect;
    if (crop == null || image == null || image.width == 0) return null;
    final ratio = widget.photo.width / image.width;
    final full = Rect.fromLTWH(0, 0, widget.photo.width.toDouble(), widget.photo.height.toDouble());
    final area = Rect.fromLTRB(
      (crop.left - image.left) * ratio,
      (crop.top - image.top) * ratio,
      (crop.right - image.left) * ratio,
      (crop.bottom - image.top) * ratio,
    ).intersect(full);
    return area.width < 1 || area.height < 1 ? null : area;
  }

  Future<void> _done() async {
    final area = _area;
    if (area == null) return;
    setState(() => _saving = true);
    final result = await cropPhoto(widget.photo.bytes, area, widget.maxSide);
    if (!mounted) return;
    if (result == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사진을 자르지 못했어요. 다른 사진으로 해 볼까요?')));
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: '취소',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isProfile ? '프로필 사진 편집' : '사진 편집',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _ready && !_saving ? _done : null,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('완료',
                    style: TextStyle(color: AppColors.primaryPink, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                // 편집 칸을 사진(프로필은 정사각형) 비율로 맞춰서 처음엔 사진 전체가 꽉 차게 보이게 함
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _isProfile ? 1 : widget.photo.width / widget.photo.height,
                    child: Crop(
                      image: widget.photo.bytes,
                      controller: _controller,
                      // 완료는 화면 기준 틀로 직접 잘라서(브라우저 canvas, 빠름) onCropped는 쓰지 않음
                      onCropped: (_) {},
                      aspectRatio: _isProfile ? 1 : _ratios[_ratioIndex].value,
                      withCircleUi: _isProfile,
                      interactive: true,
                      fixCropRect: _isProfile,
                      // 프로필: 편집 칸의 90% 크기 동그라미를 가운데에 / 사진: 사진 전체에서 시작
                      initialRectBuilder: _isProfile
                          ? InitialRectBuilder.withBuilder((viewport, _) => Rect.fromCenter(
                                center: viewport.center,
                                width: viewport.shortestSide * 0.9,
                                height: viewport.shortestSide * 0.9,
                              ))
                          : InitialRectBuilder.withSizeAndRatio(size: 1, aspectRatio: _ratios[_ratioIndex].value),
                      baseColor: Colors.black,
                      maskColor: Colors.black.withValues(alpha: 0.6),
                      radius: 0,
                      onMoved: (rect, _) => _cropRect = rect,
                      onImageMoved: (rect) => _imageRect = rect,
                      onStatusChanged: (status) {
                        final ready = status == CropStatus.ready;
                        if (ready != _ready) setState(() => _ready = ready);
                      },
                      cornerDotBuilder: (size, edge) =>
                          _isProfile ? const SizedBox.shrink() : const DotControl(color: Colors.white, padding: 8),
                      progressIndicator: const CircularProgressIndicator(color: Colors.white),
                      overlayBuilder: (_, __) => CustomPaint(painter: _CropFramePainter(circle: _isProfile)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _isProfile ? '사진을 끌어서 옮기고, 두 손가락이나 마우스 휠로 확대·축소해요' : '모서리를 끌어서 자르고, 두 손가락이나 마우스 휠로 확대·축소해요',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
            if (!_isProfile)
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: _ratios.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = i == _ratioIndex;
                    return Material(
                      color: selected ? AppColors.primaryPink : Colors.white.withValues(alpha: 0.12),
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          setState(() => _ratioIndex = i);
                          _controller.aspectRatio = _ratios[i].value;
                          // 자유는 정사각형 대신 사진 전체에서 시작
                          if (_ratios[i].value == null) {
                            _controller.area =
                                Rect.fromLTWH(0, 0, widget.photo.width.toDouble(), widget.photo.height.toDouble());
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Text(_ratios[i].label,
                                style: TextStyle(
                                    color: selected ? Colors.white : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 자르기 틀: 흰 테두리 + 3등분 안내선 (프로필은 동그라미 테두리만)
class _CropFramePainter extends CustomPainter {
  const _CropFramePainter({required this.circle});

  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    if (circle) {
      canvas.drawOval(rect.deflate(0.75), border);
      return;
    }
    canvas.drawRect(rect.deflate(0.75), border);
    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3, y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) => oldDelegate.circle != circle;
}
