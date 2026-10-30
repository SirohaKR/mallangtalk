import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/core/network/conversation_context.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:mallangtalk/shared/utils/dialogue_input.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('메뉴로 장면을 끝내고 기록은 유지하며 다음 전송에 구분선을 중복 생성하지 않음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    var now = testNow();
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(tester, roomId: room, extra: [
      ...testAiOverrides,
      clockProvider.overrideWithValue(() => now)
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = container.read(chatRoomProvider(room).notifier);
    notifier.sendUserMessage(text: '저녁 먹으러 가자');
    await settle(tester);
    final count = container.read(chatRoomProvider(room)).messages.length;
    now = now.add(const Duration(minutes: 20));
    // 채팅창 명령어 /구분선
    await tester.enterText(find.byType(TextField), '/구분선');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(container.read(chatRoomProvider(room)).messages.length, count + 1);
    expect(container.read(chatRoomProvider(room)).messages.last.text, '대화 끝');
    notifier.endConversation();
    notifier.sendUserMessage(text: '(답장하지 않는다)');
    expect(
        container
            .read(chatRoomProvider(room))
            .messages
            .where((m) => m.isConversationBreak),
        hasLength(1));
    await settle(tester);
  });
  test('행동 지시와 실제 발화를 구분하고 이전 장면을 배경 기억으로 분리', () {
    expect(stageDirectionOf('(답장하지 않는다)'), '답장하지 않는다');
    expect(stageDirectionOf('*창밖을 바라본다*'), '창밖을 바라본다');
    expect(stageDirectionOf('오늘(진짜) 바빴어'), isNull);
    final messages = [
      ChatMessageLog(
          id: 'old',
          isUser: false,
          speakerCharacterId: 'c',
          speakerName: '캐릭터',
          text: '식당에서 기다릴게',
          timestamp: DateTime(2026)),
      ChatMessageLog(
          id: 'break',
          isUser: false,
          isSystem: true,
          isConversationBreak: true,
          speakerCharacterId: 'system',
          speakerName: '',
          text: '대화 끝',
          timestamp: DateTime(2026)),
      ChatMessageLog(
          id: 'new',
          isUser: true,
          speakerCharacterId: 'u',
          speakerName: '나',
          text: '*창밖을 바라본다*',
          timestamp: DateTime(2026)),
    ];
    final transcript = conversationTranscript(messages, '나', '캐릭터');
    expect(transcript.split('[현재 장면]').last, isNot(contains('식당')));
    expect(transcript, contains('배경 기억용'));
    expect(transcript, contains('발화 아님: 창밖을 바라본다'));
    expect(activeConversation(messages).single.id, 'new');
  });
}
