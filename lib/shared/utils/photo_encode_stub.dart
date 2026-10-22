import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 웹이 아닐 때(테스트 등): Flutter로 줄여서 PNG로 저장
Future<String?> encodePhoto(Uint8List bytes, int maxSide) async {
  final source = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  final scale = maxSide / (source.width > source.height ? source.width : source.height);
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: scale < 1 ? (source.width * scale).round() : source.width,
    targetHeight: scale < 1 ? (source.height * scale).round() : source.height,
  );
  final png = await (await codec.getNextFrame()).image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
}
