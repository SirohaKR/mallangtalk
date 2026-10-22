import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/core/network/server_info.dart';
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
    await choose(tester, '다음엔 직접 두부 보러 가겠다고 하기');
    expect(find.text('다음 날 새벽'), findsOneWidget);

    final container = await openChat(tester);
    final state = container.read(chatRoomProvider(dohaId));
    expect(state.completedEventIds, ['evt_dubu_missing', 'daily_lunch_menu']);
    expect(state.unlockedCutsceneEventIds, ['evt_dubu_missing']);
    expect(state.internalAffection, 11);
    expect(state.messages.first.text, '어느 토요일 아침'); // 지난 대화 기록 복원
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

    expect(fake.lastProvider, AiProvider.claude); // 예전에 저장한 Claude 키도 그대로 쓰임
    expect(fake.lastModel, 'claude-haiku-5-5');
    expect(fake.lastUserName, '쨋뀨'); // 이 대화에서 정한 별명으로 불림
    expect(fake.lastSystemSheet, contains('비밀(유저는 아직 모름'));
    expect(fake.lastNewMessages, ['두부 잘 있어?', '보고 싶다']);
    expect(fake.lastHistory.any((m) => m.text == '보고 싶다'), isFalse);
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).internalAffection, before + 2);
  });

  testWidgets('설정에서 고른 AI 회사의 키와 모델로 자유대화를 부름', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_claude_api_key': 'sk-ant-test-key-1234',
      'byok_provider': 'gemini',
      'byok_key_gemini': 'AIza-test-key-5678',
      'byok_model_gemini': 'gemini-3.8-flash',
    });
    final fake = _FakeClaude();
    final container = await openChat(
      tester,
      extra: [claudeChatClientProvider.overrideWithValue(fake)],
    );
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);
    notifier.sendUserMessage(text: '안녕');
    await settle(tester);

    expect(fake.lastProvider, AiProvider.gemini);
    expect(fake.lastModel, 'gemini-3.8-flash');
  });

  testWidgets('말랑톡 서버에서 열면 내 키 없이 서버 키로 자유대화를 부름', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_provider': 'gemini',
      'server_access_code': 'mallang',
    });
    final fake = _FakeClaude();
    final container = await openChat(
      tester,
      extra: [
        claudeChatClientProvider.overrideWithValue(fake),
        serverInfoProvider.overrideWith((ref) async => const ServerInfo(
              baseUrl: 'http://nas.local:8080',
              providers: {AiProvider.gemini},
              needsAccessCode: true,
            )),
      ],
    );
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);
    notifier.sendUserMessage(text: '안녕');
    await settle(tester);

    expect(fake.lastProvider, AiProvider.gemini);
    expect(fake.lastApiKey, '');
    expect(fake.lastRelay?.baseUrl, 'http://nas.local:8080');
    expect(fake.lastRelay?.accessCode, 'mallang');
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
  });
}

class _FakeClaude extends ClaudeChatClient {
  _FakeClaude() : super(dio: Dio());

  AiProvider? lastProvider;
  String? lastApiKey;
  AiRelay? lastRelay;
  String? lastModel;
  String? lastUserName;
  String? lastSystemSheet;
  List<String> lastNewMessages = const [];
  List<ChatMessageLog> lastHistory = const [];

  @override
  Future<FreeChatReply> reply({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
    String userName = '너',
    String userIntro = '',
  }) async {
    lastProvider = provider;
    lastApiKey = apiKey;
    lastRelay = relay;
    lastModel = model;
    lastUserName = userName;
    lastSystemSheet = character.aiCharacterSheet;
    lastNewMessages = newUserMessages;
    lastHistory = history;
    return const FreeChatReply(
      bubbles: ['ㅇㅇ 잘 있음', '두부 지금 내 배 위에서 자'],
      affectionDelta: 2,
    );
  }
}
