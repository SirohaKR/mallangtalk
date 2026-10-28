import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:web/web.dart' as web;

/// 편집 화면에 올릴 사진 (줄인 내용 + 가로·세로 크기)
typedef PreparedPhoto = ({Uint8List bytes, int width, int height});

Future<web.HTMLImageElement> _load(String url) async {
  final img = web.HTMLImageElement()..src = url;
  await img.onLoad.first.timeout(const Duration(seconds: 20));
  return img;
}

/// 웹: 브라우저 canvas로 줄임. 편집 화면이 가볍게 열리도록 긴 쪽 [maxSide]로 먼저 줄여 둠.
/// (폰 사진 회전 정보도 브라우저가 이때 반영해 줘요)
Future<PreparedPhoto?> preparePhoto(Uint8List bytes, int maxSide) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  try {
    final img = await _load(url);
    final w = img.naturalWidth, h = img.naturalHeight;
    if (w == 0 || h == 0) return null;
    final dataUrl = _draw(img, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), maxSide, 0.92);
    final scale = maxSide / (w > h ? w : h);
    return (
      bytes: base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
      width: scale < 1 ? (w * scale).round() : w,
      height: scale < 1 ? (h * scale).round() : h,
    );
  } catch (_) {
    return null;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

/// 웹: 편집 화면에서 고른 영역([area], 사진 기준 좌표)만 잘라 긴 쪽 [maxSide]로 줄여 JPEG로 저장
Future<String?> cropPhoto(Uint8List bytes, Rect area, int maxSide) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  try {
    return _draw(await _load(url), area, maxSide, 0.88);
  } catch (_) {
    return null;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

String _draw(web.HTMLImageElement img, Rect area, int maxSide, double quality) {
  final longSide = area.width > area.height ? area.width : area.height;
  final scale = maxSide / longSide;
  final width = (scale < 1 ? area.width * scale : area.width).round().clamp(1, 100000);
  final height = (scale < 1 ? area.height * scale : area.height).round().clamp(1, 100000);
  final canvas = web.HTMLCanvasElement()
    ..width = width
    ..height = height;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  ctx.fillStyle = '#ffffff'.toJS; // 투명 PNG는 흰 바탕으로
  ctx.fillRect(0, 0, width, height);
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(img, area.left, area.top, area.width, area.height, 0, 0, width, height);
  return canvas.toDataURL('image/jpeg', quality.toJS);
}
