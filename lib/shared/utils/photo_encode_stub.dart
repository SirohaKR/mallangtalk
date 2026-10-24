import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 편집 화면에 올릴 사진 (줄인 내용 + 가로·세로 크기)
typedef PreparedPhoto = ({Uint8List bytes, int width, int height});

Future<ui.Image> _decode(Uint8List bytes, {int? width, int? height}) async =>
    (await (await ui.instantiateImageCodec(bytes, targetWidth: width, targetHeight: height)).getNextFrame())
        .image;

/// 웹이 아닐 때(테스트 등): 긴 쪽 [maxSide]로 줄인 PNG
Future<PreparedPhoto?> preparePhoto(Uint8List bytes, int maxSide) async {
  final source = await _decode(bytes);
  final scale = maxSide / (source.width > source.height ? source.width : source.height);
  if (scale >= 1) return (bytes: bytes, width: source.width, height: source.height);
  final resized = await _decode(bytes,
      width: (source.width * scale).round(), height: (source.height * scale).round());
  final png = await resized.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  return (bytes: png.buffer.asUint8List(), width: resized.width, height: resized.height);
}

/// 웹이 아닐 때: [area]만 잘라 긴 쪽 [maxSide]로 줄인 PNG
Future<String?> cropPhoto(Uint8List bytes, ui.Rect area, int maxSide) async {
  final source = await _decode(bytes);
  final longSide = area.width > area.height ? area.width : area.height;
  final scale = maxSide / longSide;
  final width = (scale < 1 ? area.width * scale : area.width).round().clamp(1, 100000);
  final height = (scale < 1 ? area.height * scale : area.height).round().clamp(1, 100000);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    area,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
}
