import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/shared/utils/photo_encode_stub.dart';
import 'package:mallangtalk/shared/widgets/photo_crop_screen.dart';

/// 가로 [w] × 세로 [h] 짜리 PNG 한 장
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFE86A92));
  final image = await recorder.endRecording().toImage(w, h);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<ui.Size> _sizeOf(String dataUrl) async {
  final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  return ui.Size(image.width.toDouble(), image.height.toDouble());
}

/// 편집 화면을 띄우고 '완료'를 눌러 돌려받은 사진 주소
Future<String?> _cropWith(WidgetTester tester, PhotoCropShape shape, int maxSide, {String? ratio}) async {
  final photo = (await tester.runAsync(() async => preparePhoto(await _png(800, 400), 1600)))!;
  String? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<String>(MaterialPageRoute(
            builder: (_) => PhotoCropScreen(photo: photo, shape: shape, maxSide: maxSide),
          ));
        },
        child: const Text('열기'),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1)); // 화면 넘어가는 애니메이션
  // 사진 읽기는 실제 시간이 걸려서 잠깐 기다려 줌
  for (var i = 0; i < 300 && !_doneEnabled(tester); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_doneEnabled(tester), isTrue, reason: '사진을 다 읽으면 완료 버튼이 켜짐');
  if (ratio != null) {
    await tester.tap(find.text(ratio));
    await tester.pump();
  }
  await tester.tap(find.text('완료'));
  for (var i = 0; i < 100 && result == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
  return result;
}

bool _doneEnabled(WidgetTester tester) => tester
    .widgetList<TextButton>(find.ancestor(of: find.text('완료'), matching: find.byType(TextButton)))
    .any((b) => b.onPressed != null);

void main() {
  testWidgets('프로필 사진은 동그라미 틀 1:1로 잘려서 384px 이하로 나옴', (tester) async {
    final url = await _cropWith(tester, PhotoCropShape.profile, 384);
    expect(url, startsWith('data:image/'));
    final size = (await tester.runAsync(() => _sizeOf(url!)))!;
    expect(size.width, size.height);
    expect(size.width, lessThanOrEqualTo(384));
    expect(find.text('프로필 사진 편집'), findsNothing); // 완료 뒤 닫힘
  });

  testWidgets('사진은 원본 비율 그대로, 1:1을 고르면 정사각형으로 잘림', (tester) async {
    final original = await _cropWith(tester, PhotoCropShape.photo, 960);
    final originalSize = (await tester.runAsync(() => _sizeOf(original!)))!;
    expect(originalSize.width / originalSize.height, closeTo(2, 0.05));

    final square = await _cropWith(tester, PhotoCropShape.photo, 960, ratio: '1:1');
    final squareSize = (await tester.runAsync(() => _sizeOf(square!)))!;
    expect(squareSize.width / squareSize.height, closeTo(1, 0.05));
  });
}
