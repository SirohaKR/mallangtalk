import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// 웹: 브라우저 canvas로 줄여서 JPEG로 저장 (PNG보다 사진이 5~10배 작아요)
Future<String?> encodePhoto(Uint8List bytes, int maxSide) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  try {
    final img = web.HTMLImageElement()..src = url;
    await img.onLoad.first.timeout(const Duration(seconds: 20));
    final w = img.naturalWidth, h = img.naturalHeight;
    if (w == 0 || h == 0) return null;
    final scale = maxSide / (w > h ? w : h);
    final width = scale < 1 ? (w * scale).round() : w;
    final height = scale < 1 ? (h * scale).round() : h;
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.fillStyle = '#ffffff'.toJS; // 투명 PNG는 흰 바탕으로
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(img, 0, 0, width, height);
    return canvas.toDataURL('image/jpeg', 0.82.toJS);
  } catch (_) {
    return null;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
