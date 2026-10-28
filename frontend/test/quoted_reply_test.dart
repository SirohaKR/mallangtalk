import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('말풍선을 길게 눌러 답장하고 인용을 저장·복원', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container
        .read(chatRoomProvider(room).notifier)
        .sendUserMessage(text: '오늘 어디 갈까?');
    await settle(tester);
    final target = container.read(chatRoomProvider(room)).messages.first;
    await tester.longPress(find.text('오늘 어디 갈까?'));
    await tester.pump();
    expect(find.byKey(const ValueKey('reply_preview')), findsOneWidget);
    await tester.enterText(find.byType(TextField), '공원 가자');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
    final reply = container
        .read(chatRoomProvider(room))
        .messages
        .singleWhere((m) => m.text == '공원 가자');
    expect(reply.replyToId, target.id);
    expect(reply.replyToText, target.text);
    expect(find.byKey(const ValueKey('reply_preview')), findsNothing);
    expect(find.byKey(ValueKey('quoted_${reply.id}')), findsOneWidget);
    final reopened =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    expect(
        reopened
            .read(chatRoomProvider(room))
            .messages
            .singleWhere((m) => m.text == '공원 가자')
            .replyToId,
        target.id);
    await tester.longPress(find.text('공원 가자'));
    await tester.pump();
    await tester.tap(find.byTooltip('답장 취소'));
    await tester.pump();
    expect(find.byKey(const ValueKey('reply_preview')), findsNothing);
  });
  test('기존 메시지는 인용 필드 없이 읽고 읽음 변경 시 인용을 보존', () {
    final message = ChatMessageLog(
        id: 'r',
        isUser: true,
        speakerCharacterId: 'u',
        speakerName: '나',
        text: '답장',
        timestamp: DateTime(2026),
        replyToId: 'old',
        replyToName: '상대',
        replyToText: '원문');
    expect(
        ChatMessageLog.fromJson(message.copyWith(isUnread: true).toJson())
            .replyToText,
        '원문');
    expect(ChatMessageLog.fromJson({'id': 'legacy'}).replyToId, isNull);
  });
}
