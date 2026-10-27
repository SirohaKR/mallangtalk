import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('전송 버튼을 반복해서 눌러도 포커스와 키보드 높이가 유지되고 닫으면 복구됨', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester, roomId: freeRoomId(dohaId));
    addTearDown(tester.view.resetViewInsets);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final input = find.byType(TextField);
    final send = find.widgetWithIcon(IconButton, Icons.send_rounded);
    final originalBottom = tester.getBottomLeft(input).dy;
    final field = tester.widget<EditableText>(find.byType(EditableText));

    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final keyboardBottom = tester.getBottomLeft(input).dy;
    expect(keyboardBottom, closeTo(originalBottom - 300, 1));

    for (final text in ['첫 번째', '두 번째', '세 번째']) {
      await tester.enterText(input, text);
      await tester.tap(send);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, isEmpty);
      expect(tester.getBottomLeft(input).dy, closeTo(keyboardBottom, 1));
    }
    final sent = container.read(chatRoomProvider(freeRoomId(dohaId)))
        .messages.where((m) => m.isUser).map((m) => m.text);
    expect(sent, containsAllInOrder(['첫 번째', '두 번째', '세 번째']));

    // Android 뒤로 가기로 키보드만 닫으면 입력창 포커스는 남을 수 있다.
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(field.focusNode.hasFocus, isTrue);
    expect(tester.getBottomLeft(input).dy, closeTo(originalBottom, 1));
    await settle(tester);
  });

  testWidgets('키보드가 닫히고 포커스가 없는 상태에서 전송해도 다시 포커스를 강제하지 않음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    await openDohaChat(tester, roomId: freeRoomId(dohaId));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byType(TextField), '보낼 내용');
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.unfocus();
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send_rounded));
    await tester.pump();
    expect(field.focusNode.hasFocus, isFalse);
    expect(field.controller.text, isEmpty);
    await settle(tester);
  });
}
