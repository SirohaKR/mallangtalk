import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 진행 저장(새로고침 후 이어하기)과 내 AI 키 자유대화를 확인하는 테스트입니다.
void main() {
  Future<ProviderContainer> openChat(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) =>
      openDohaChat(tester, extra: extra);

  testWidgets('새로고침해도 끝낸 이벤트와 모은 컷씬이 남음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    await openChat(tester);
    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    await closeCutscene(tester);
    await choose(tester, '다음엔 직접 두부 보러 가겠다고 하기');
    expect(find.text('화요일 오전 6:40'), findsOneWidget);

    final container = await openChat(tester);
    final state = container.read(chatRoomProvider(dohaId));
    expect(state.completedEventIds, ['evt_dubu_missing', 'daily_lunch_menu']);
    expect(state.unlockedCutsceneEventIds, ['evt_dubu_missing']);
    expect(state.internalAffection, 11);
    expect(state.messages.first.text, '토요일 오전 10:24'); // 지난 대화 기록 복원
    expect(find.widgetWithText(ElevatedButton, '다음엔 나도 같이 뛰자고 하기'), findsOneWidget);
  });

  testWidgets('키가 있으면 자유대화에 AI 답장과 호감도 변화가 반영됨', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_claude_api_key': 'sk-ant-test-key-1234',
      'byok_claude_model': 'claude-haiku-5-5',
    });
    final fake = _FakeClaude();
    final container = await openChat(
      tester,
      extra: [claudeChatClientProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);
    final before = container.read(chatRoomProvider(dohaId)).internalAffection;

    notifier.sendUserMessage(text: '두부 잘 있어?');
    notifier.sendUserMessage(text: '보고 싶다');
    await settle(tester);

    expect(fake.lastModel, 'claude-haiku-5-5');
    expect(fake.lastNewMessages, ['두부 잘 있어?', '보고 싶다']);
    expect(fake.lastHistory.any((m) => m.text == '보고 싶다'), isFalse);
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).internalAffection, before + 2);
  });
}

class _FakeClaude extends ClaudeChatClient {
  _FakeClaude() : super(dio: Dio());

  String? lastModel;
  List<String> lastNewMessages = const [];
  List<ChatMessageLog> lastHistory = const [];

  @override
  Future<FreeChatReply> reply({
    required String apiKey,
    required String model,
    required CharacterModel character,
    required String stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
  }) async {
    lastModel = model;
    lastNewMessages = newUserMessages;
    lastHistory = history;
    return const FreeChatReply(
      bubbles: ['ㅇㅇ 잘 있음', '두부 지금 내 배 위에서 자'],
      affectionDelta: 2,
    );
  }
}
