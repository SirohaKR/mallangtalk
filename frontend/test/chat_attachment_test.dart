import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('키가 없으면 등록 안내를 띄우고 입력을 보존하며 예시 답장을 만들지 않음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(tester, roomId: room);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byType(TextField), '안녕');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('API 키를 등록해 주세요'), findsOneWidget);
    expect(find.text('API 키 등록'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '안녕');
    expect(container.read(chatRoomProvider(room)).messages, isEmpty);
    await tester.tap(find.text('취소'));
    await settle(tester);
    expect(
        container
            .read(chatRoomProvider(room))
            .messages
            .where((m) => !m.isSystem),
        isEmpty);
    expect(
        container
            .read(chatRoomProvider(room).notifier)
            .sendUserMessage(text: '직접 호출'),
        isFalse);
    await settle(tester);
    expect(
        container
            .read(chatRoomProvider(room))
            .messages
            .every((m) => m.isSystem),
        isTrue);
  });

  testWidgets('갤러리에서 선택한 실제 이미지와 문구를 전송하고 재진입해도 보존', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final image =
        'data:image/png;base64,${base64Encode(File('web/icons/Icon-192.png').readAsBytesSync())}';
    final room = freeRoomId(dohaId);
    var picked = 0;
    final container = await openDohaChat(tester, roomId: room, extra: [
      ...testAiOverrides,
      chatPhotoPickerProvider.overrideWithValue((context) async {
        picked++;
        return image;
      }),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byType(TextField), '이 사진 어때?');
    await tester.tap(find.byTooltip('갤러리 사진 첨부'));
    await tester.pump();
    await settle(tester);
    expect(picked, 1);
    final sent = container
        .read(chatRoomProvider(room))
        .messages
        .singleWhere((m) => m.isUser);
    expect(sent.text, '이 사진 어때?');
    expect(sent.photoImage, image);
    expect(sent.hasPhoto, isTrue);
    expect(
        container
            .read(localStoreProvider)
            .loadRun(room)!
            .messages
            .first
            .photoImage,
        image);
    final reopened =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    expect(
        reopened.read(chatRoomProvider(room)).messages.first.photoImage, image);
  });

  testWidgets('사진 선택 취소 시 문구와 대화 기록을 그대로 둠', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(tester, roomId: room, extra: [
      ...testAiOverrides,
      chatPhotoPickerProvider.overrideWithValue((context) async => null),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byType(TextField), '작성 중');
    await tester.tap(find.byTooltip('갤러리 사진 첨부'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '작성 중');
    expect(container.read(chatRoomProvider(room)).messages, isEmpty);
  });
}
