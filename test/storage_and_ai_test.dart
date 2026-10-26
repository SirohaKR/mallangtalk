import 'dart:async';
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

  testWidgets('이벤트 중간에 나갔다 들어오면 그 자리(선택지·말풍선)부터 이어짐', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    await openChat(tester);
    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    final before = dohaState(tester);
    expect(before.currentChoices, isNotEmpty); // 첫 이벤트 두 번째 선택지에서 나감
    expect(before.completedEventIds, isEmpty);

    // 새로 띄우면 처음부터 다시 치지 않고 같은 대화·같은 선택지
    final container = await openChat(tester);
    final after = container.read(chatRoomProvider(dohaId));
    expect(after.messages.map((m) => m.text), before.messages.map((m) => m.text));
    expect(after.currentEventId, before.currentEventId);
    expect(after.currentChoices.map((c) => c.buttonLabel), before.currentChoices.map((c) => c.buttonLabel));
    expect(after.internalAffection, before.internalAffection);

    // 말풍선을 치던 중에 나가도 이미 온 말풍선은 남고 다음 말풍선부터
    container.read(chatRoomProvider(dohaId).notifier).selectChoice(after.currentChoices.first);
    var mid = after;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      mid = container.read(chatRoomProvider(dohaId));
      if (mid.messages.length > after.messages.length + 2 && mid.currentChoices.isEmpty) break;
    }
    final midTexts = mid.messages.map((m) => m.text).toList();
    final reopened = (await openChat(tester)).read(chatRoomProvider(dohaId));
    expect(reopened.messages.length, greaterThanOrEqualTo(after.messages.length));
    expect(midTexts.take(reopened.messages.length), reopened.messages.map((m) => m.text).take(midTexts.length));
    expect(reopened.messages.where((m) => m.text == midTexts.last).length, 1); // 같은 말풍선이 두 번 오지 않음
  });

  testWidgets('키가 있으면 자유대화에 AI 답장과 호감도 변화가 반영됨', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      ...freeTalkOpen,
      'byok_claude_api_key': 'sk-ant-test-key-1234',
      'byok_claude_model': 'claude-haiku-5-5',
      'persona_$dohaId': '도하랑 같은 동네 사는 24살',
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
    expect(fake.lastPersona, '도하랑 같은 동네 사는 24살'); // 이 대화의 내 설정을 AI가 앎
    expect(fake.lastHistory.any((m) => m.text == '보고 싶다'), isFalse);
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).internalAffection, before + 2);
  });

  testWidgets('자유대화 방: 단계 없이 부르고, 보낼 때를 정해 둔 사진만 AI에게 보여 주고, 고른 사진은 앨범으로', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_claude_api_key': 'sk-ant-test-key-1234',
    });
    final base = loadSampleBundle();
    const trigger = PhotoTrigger(caption: '두부를 배 위에 올린 셀카', mood: '뿌듯함', keywords: ['두부', '고양이']);
    final bundle = ScenarioBundle(
      character: base.character,
      events: [
        for (final e in base.events)
          if (e.id == 'evt_dubu_missing')
            ScenarioEventModel.fromJson({
              ...e.toJson(),
              'photos': ['dubu_photo', 'other_photo'],
              'photo_triggers': {'dubu_photo': trigger.toJson()},
            })
          else
            e,
      ],
      nodes: base.nodes,
    );
    expect(bundle.albumPhotos.map((p) => p.label), contains('두부를 배 위에 올린 셀카'));

    final fake = _FakeClaude()..sendPhoto = 'p1';
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(
      tester,
      roomId: room,
      bundle: bundle,
      extra: [claudeChatClientProvider.overrideWithValue(fake)],
    );
    container.read(chatRoomProvider(room).notifier).sendUserMessage(text: '두부 잘 있어?');
    await settle(tester);

    expect(fake.lastStageLabel, isNull);
    expect(fake.lastPhotos.map((p) => p.ref), ['dubu_photo']);
    final photoMsg = container.read(chatRoomProvider(room)).messages.lastWhere((m) => m.hasPhoto);
    expect(photoMsg.photoLabel, '두부를 배 위에 올린 셀카');
    expect(photoMsg.isUser, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('photos_$dohaId'), contains('두부를 배 위에 올린 셀카'));
  });

  testWidgets('설정에서 고른 AI 회사의 키와 모델로 자유대화를 부름', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      ...freeTalkOpen,
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
      ...freeTalkOpen,
      'byok_provider': 'gemini',
      'server_access_code': 'mallang',
    });
    final fake = _FakeClaude();
    final container = await openChat(
      tester,
      extra: [
        claudeChatClientProvider.overrideWithValue(fake),
        serverInfoProvider.overrideWith((ref) async => const ServerInfo(
              baseUrl: 'http://nas.local:5200',
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
    expect(fake.lastRelay?.baseUrl, 'http://nas.local:5200');
    expect(fake.lastRelay?.accessCode, 'mallang');
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
  });

  testWidgets('이야기 도중 자유대화를 켜면 선택지가 사라지고, 캐릭터가 마무리하면 미룬 이벤트가 처음부터 이어짐', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, ...freeTalkOpen, 'byok_claude_api_key': 'sk-ant-test-key-1234'});
    final fake = _FakeClaude()..endAtTurn = 2;
    final container = await openChat(tester, extra: [claudeChatClientProvider.overrideWithValue(fake)]);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    final beforeAffection = dohaState(tester).internalAffection;
    expect(beforeAffection, greaterThan(0));

    notifier.toggleDirectInputMode(true);
    await tester.pump();
    var state = dohaState(tester);
    expect(state.currentChoices, isEmpty);
    expect(state.internalAffection, 0); // 미룬 이벤트에서 고른 점수는 되돌림
    expect(find.text('하던 이야기는 자유대화가 끝나면 이어져요'), findsOneWidget);

    notifier.sendUserMessage(text: '뭐해');
    await settle(tester);
    expect(dohaState(tester).isByokAiModeEnabled, isTrue);
    notifier.sendUserMessage(text: '나 이제 자야겠다');
    await settle(tester);

    state = dohaState(tester);
    expect(find.text('내일 또 톡해'), findsOneWidget);
    expect(find.text('자유대화가 끝났어요'), findsOneWidget);
    expect(state.isByokAiModeEnabled, isFalse);
    expect(state.memories, ['두부 얘기로 한참 웃었다']);
    expect(state.internalAffection, 3); // 자유대화에서 오른 만큼만 (2 + 1)
    expect(state.completedEventIds, isEmpty);
    // 미뤘던 첫 이벤트가 처음부터 다시
    expect(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'), findsOneWidget);

    // 다음 자유대화 때 기억을 AI에게 넘김
    notifier.toggleDirectInputMode(true);
    notifier.sendUserMessage(text: '안녕');
    await settle(tester);
    expect(fake.lastMemories, ['두부 얘기로 한참 웃었다']);
  });

  testWidgets('AI가 안 끝내도 6번째부터 마무리하라고 하고 12번째에는 꼭 끝냄', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, ...freeTalkOpen, 'byok_claude_api_key': 'sk-ant-test-key-1234'});
    final fake = _FakeClaude();
    final container = await openChat(tester, extra: [claudeChatClientProvider.overrideWithValue(fake)]);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);
    for (var i = 0; i < ChatRoomNotifier.freeTalkMaxTurns; i++) {
      expect(dohaState(tester).isByokAiModeEnabled, isTrue);
      notifier.sendUserMessage(text: '얘기 $i');
      await settle(tester);
    }
    expect([for (final p in fake.paces) p.wrapUp], [for (var t = 1; t <= 12; t++) t >= 6]);
    expect(fake.paces.last.mustEnd, isTrue);
    expect(dohaState(tester).isByokAiModeEnabled, isFalse);
  });

  testWidgets('AI 답장이 실패하면 내 톡은 안 읽음으로 남고, 다시 보내기를 누르면 같이 다시 물어봄', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, ...freeTalkOpen, 'byok_claude_api_key': 'sk-ant-test-key-1234'});
    final fake = _FakeClaude()..failNext = 1;
    final container = await openChat(tester, extra: [claudeChatClientProvider.overrideWithValue(fake)]);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);
    notifier.sendUserMessage(text: '황태자 전하도');
    notifier.sendUserMessage(text: '좀 외로울거같아');
    await settle(tester);

    var state = dohaState(tester);
    expect(find.text('AI 답이 너무 오래 걸려서 끊겼어요.'), findsOneWidget);
    expect(state.canRetryFreeTalk, isTrue);
    expect(state.messages.where((m) => m.isUser && m.isUnread).length, 2);
    expect(find.text('다시 보내기'), findsOneWidget);

    await tester.tap(find.text('다시 보내기'));
    await settle(tester);
    state = dohaState(tester);
    expect(fake.lastNewMessages, ['황태자 전하도', '좀 외로울거같아']);
    expect(fake.lastHistory.any((m) => m.text == '황태자 전하도'), isFalse); // 같은 말을 두 번 보내지 않음
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
    expect(state.canRetryFreeTalk, isFalse);
    expect(find.text('다시 보내기'), findsNothing);
  });

  testWidgets('끊어서 보내다 잠깐 쉬고 또 보내면 요청을 겹쳐 보내지 않고 답이 온 뒤 전부 합쳐서 다시 물어봄', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, ...freeTalkOpen, 'byok_claude_api_key': 'sk-ant-test-key-1234'});
    final slow = Completer<void>();
    final fake = _FakeClaude()..gate = slow.future;
    final container = await openChat(tester, extra: [claudeChatClientProvider.overrideWithValue(fake)]);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.toggleDirectInputMode(true);

    notifier.sendUserMessage(text: '근데 황태자 전하도');
    notifier.sendUserMessage(text: '너 잘난거 알면');
    await tester.pump(const Duration(seconds: 3)); // 잠깐 쉼 → 첫 요청이 나감
    expect(fake.calls.length, 1);
    notifier.sendUserMessage(text: '같이 머리 맞댈 수도 있어서');
    await tester.pump(const Duration(seconds: 3)); // 첫 답을 기다리는 중에는 새 요청을 안 보냄
    expect(fake.calls.length, 1);

    slow.complete(); // 늦게 온 첫 답은 버리고 세 마디를 한꺼번에 다시 물어봄
    await settle(tester);
    expect(fake.calls.length, 2);
    expect(fake.calls.last, ['근데 황태자 전하도', '너 잘난거 알면', '같이 머리 맞댈 수도 있어서']);
    expect(find.text('두부 지금 내 배 위에서 자'), findsOneWidget);
    expect(dohaState(tester).messages.where((m) => m.isUser && m.isUnread), isEmpty);
    expect(find.textContaining('끊겼어요'), findsNothing);
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
  final paces = <FreeTalkPace>[];
  String lastPersona = '';
  /// 이만큼은 실패로 답함
  int failNext = 0;
  /// 주면 이게 끝날 때까지 답을 안 줌 (AI가 오래 걸리는 상황)
  Future<void>? gate;
  final calls = <List<String>>[];
  List<String> lastMemories = const [];
  /// 이 번째 답장에서 캐릭터가 마무리함 (null이면 AI가 스스로는 안 끝냄)
  int? endAtTurn;
  List<FreeTalkPhoto> lastPhotos = const [];
  String? lastStageLabel = '';
  /// 답장에 같이 보낼 사진 ID
  String sendPhoto = '';

  @override
  Future<FreeChatReply> reply({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String? stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
    String userName = '너',
    String userIntro = '',
    String userPersona = '',
    FreeTalkPace pace = FreeTalkPace.open,
    List<String> memories = const [],
    List<FreeTalkPhoto> photos = const [],
  }) async {
    paces.add(pace);
    lastPhotos = photos;
    lastStageLabel = stageLabel;
    lastPersona = userPersona;
    calls.add(newUserMessages);
    final waitFor = gate;
    gate = null;
    if (waitFor != null) await waitFor;
    if (failNext > 0) {
      failNext--;
      throw const ClaudeChatException('AI 답이 너무 오래 걸려서 끊겼어요.');
    }
    lastMemories = memories;
    if (pace.turn == endAtTurn || pace.mustEnd) {
      return const FreeChatReply(
        bubbles: ['아 나 이제 씻으러 가야겠다', '내일 또 톡해'],
        affectionDelta: 1,
        ends: true,
        memory: '두부 얘기로 한참 웃었다',
      );
    }
    lastProvider = provider;
    lastApiKey = apiKey;
    lastRelay = relay;
    lastModel = model;
    lastUserName = userName;
    lastSystemSheet = character.aiCharacterSheet;
    lastNewMessages = newUserMessages;
    lastHistory = history;
    return FreeChatReply(
      bubbles: const ['ㅇㅇ 잘 있음', '두부 지금 내 배 위에서 자'],
      affectionDelta: 2,
      photoId: sendPhoto,
    );
  }
}
