import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 샘플 시나리오(윤도하)를 실제 화면에서 끝까지 플레이해 보는 테스트입니다.
void main() {
  Future<ProviderContainer> openChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    return openDohaChat(tester);
  }

  testWidgets('호감도 이벤트를 다 끝내면 엔딩 후 공략 완료', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    expect(state().isByokAiModeEnabled, isFalse);
    expect(find.text('어느 토요일 아침'), findsOneWidget);

    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    // 2단계 대사가 끝나면 컷씬이 팝업 없이 앨범에 바로 들어감
    expect(state().unlockedCutsceneEventIds, contains('evt_dubu_missing'));
    expect(find.textContaining('화면을 탭하면 계속'), findsNothing);
    await choose(tester, '다음엔 직접 두부 보러 가겠다고 하기');

    expect(find.text('다음 날 새벽'), findsOneWidget);
    await choose(tester, '다음엔 나도 같이 뛰자고 하기');

    await choose(tester, '좋다고, 무슨 밴드냐고 묻기');
    expect(state().unlockedCutsceneEventIds, contains('evt_gig_tickets'));
    await choose(tester, '근데 왜 하필 내 생각이 났냐고 묻기');

    await choose(tester, '다음에 나한테도 하나 만들어 달라고 하기');

    await choose(tester, '내 생일 기억한 거냐고 묻기');
    await choose(tester, '1년 동안 받은 선물 중에 제일 좋다고 하기');

    await choose(tester, '우리 처음 만난 날이라고 답하기');
    await choose(tester, '나도 그날 기억난다고, USB 얘기 꺼내기');
    expect(state().unlockedCutsceneEventIds, contains('evt_first_year'));
    await choose(tester, '지금 간다고 하기');

    expect(find.text('그날 늦은 밤'), findsOneWidget);
    await choose(tester, '좋다고 대답하기');
    expect(state().progress, StoryProgress.cleared);
    expect(state().unlockedCutsceneEventIds, hasLength(4));
    expect(find.text('윤도하 공략 완료'), findsOneWidget);
    await skipDailyTalks(tester);
    expect(find.textContaining('처음부터 다시 하기'), findsOneWidget);
  });

  testWidgets('공연을 거절해 사진을 놓쳐도 엔딩은 나오고, 공략 뒤 안 본 갈래 다시 보기로 모음', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    final notifier = container.read(chatRoomProvider(dohaId).notifier);

    await choose(tester, '츄르 봉지를 흔들어 보라고 하기');
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '다음엔 나도 같이 뛰자고 하기');
    expect(state().sparkleChoiceIds, isEmpty, reason: '첫 회차엔 반짝이 없음');
    await choose(tester, '토요일엔 선약이 있다고 거절하기');
    expect(state().unlockedCutsceneEventIds, isNot(contains('evt_gig_tickets')));
    await choose(tester, '누가 봐도 하트라고 해주기');
    await choose(tester, '2분 뒤에 뭐가 있냐고 묻기');
    await choose(tester, '들어보고 울컥했다고 말하기');
    await choose(tester, '모르는 척하기');
    await choose(tester, '장난이었다고 사과하기');
    await choose(tester, '지금 간다고 하기');

    // 사진을 다 못 모아도 엔딩
    expect(find.text('그날 늦은 밤'), findsOneWidget);
    await choose(tester, '좋다고 대답하기');
    expect(state().progress, StoryProgress.cleared);
    expect(notifier.missedPhotoCount, greaterThan(0));
    final replayable = notifier.replayableEvents.map((r) => r.event.id);
    expect(replayable, contains('evt_gig_tickets'));
    expect(find.byKey(const ValueKey('replay_button')), findsOneWidget);
    // 공략 완료 패널: 호감도 이벤트 수·앨범 수·엔딩 다시 보기
    expect(find.text('호감도 이벤트'), findsOneWidget);
    expect(find.text('앨범 사진'), findsOneWidget);
    expect(find.byKey(const ValueKey('ending_replay')), findsOneWidget);
    expect(find.textContaining('${notifier.missedPhotoCount}장'), findsWidgets);

    // 다시 보기: 안 고른 선택지에 반짝이, 사진은 모이고 진행은 그대로
    final affection = state().internalAffection;
    final completed = state().completedEventIds;
    await tester.tap(find.byKey(const ValueKey('replay_button')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 못 받은 사진 모으기: 갈래마다 '…를 골랐다면 · 사진 N장'
    final branches = notifier.missedBranches;
    final gig = branches.indexWhere((b) => b.event.id == 'evt_gig_tickets' && b.choiceLabel == '좋다고, 무슨 밴드냐고 묻기');
    expect(gig, isNot(-1));
    expect(branches[gig].photos, greaterThan(0));
    final row = find.byKey(ValueKey('missed_evt_gig_tickets_$gig'));
    expect(find.descendant(of: row, matching: find.textContaining('"좋다고, 무슨 밴드냐고 묻기"를 골랐다면')), findsOneWidget);
    await tester.tap(find.descendant(of: row, matching: find.text('다시 보기')));
    await settle(tester);
    expect(state().isReplaying, isTrue);
    expect(find.byKey(const ValueKey('replay_button')), findsNothing);
    final yes = state().currentChoices.firstWhere((c) => c.buttonLabel == '좋다고, 무슨 밴드냐고 묻기');
    expect(state().sparkleChoiceIds, contains(yes.id));
    expect(find.byKey(ValueKey('choice_new_${yes.id}')), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, yes.buttonLabel));
    await settle(tester);
    expect(state().unlockedCutsceneEventIds, contains('evt_gig_tickets'));
    while (state().currentChoices.isNotEmpty) {
      await tester.tap(find.widgetWithText(ElevatedButton, state().currentChoices.first.buttonLabel));
      await settle(tester);
    }
    expect(state().isReplaying, isFalse);
    expect(state().progress, StoryProgress.cleared);
    expect(state().internalAffection, affection);
    expect(state().completedEventIds, completed);
    expect(find.text('다시 보기가 끝났어요'), findsOneWidget);

    // 다음 회차: 첫 대화부터 예전에 안 고른 선택지에 반짝이
    await tester.tap(find.textContaining('처음부터 다시 하기'));
    await settle(tester);
    expect(state().progress, StoryProgress.playing);
    final first = state().currentChoices.firstWhere((c) => c.buttonLabel == '지금 바로 같이 찾으러 가겠다고 하기');
    final picked = state().currentChoices.firstWhere((c) => c.buttonLabel == '츄르 봉지를 흔들어 보라고 하기');
    expect(state().sparkleChoiceIds, contains(first.id));
    expect(state().sparkleChoiceIds, isNot(contains(picked.id)));
  });

  testWidgets('이어지는 대화는 앞 대화 바로 뒤에 오고, 일상 대화 순서는 주사위로 정함', (tester) async {
    final base = loadSampleBundle();
    final bundle = ScenarioBundle(
      character: base.character,
      events: [
        for (final e in base.events)
          if (e.id == 'daily_rain')
            ScenarioEventModel.fromJson({...e.toJson(), 'follows': 'evt_dubu_missing'})
          else
            e,
      ],
      nodes: base.nodes,
    );
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester, bundle: bundle);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    await tester.tap(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '다음엔 직접 두부 보러 가겠다고 하기'));
    await settle(tester);
    expect(state().currentEventId, 'daily_rain', reason: '두부 사건 바로 뒤에 붙여 둔 비 오는 날 대화');
  });

  testWidgets('공략 후 이야기는 엔딩 뒤에 순서대로 옴', (tester) async {
    final base = loadSampleBundle();
    final bundle = ScenarioBundle(
      character: base.character,
      events: [
        for (final e in base.events)
          if (e.id == 'daily_weird_dream')
            ScenarioEventModel.fromJson({...e.toJson(), 'event_type': ScenarioEventType.afterEnding})
          else
            e,
      ],
      nodes: base.nodes,
    );
    final run = SavedRun(
      affection: 100,
      flags: const [],
      completedEventIds: [
        for (final e in bundle.events)
          if ((e.isAffectionEvent || e.isDaily) && e.id != 'daily_weird_dream') e.id,
      ],
      messages: const [],
      cleared: true,
    );
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$dohaId': jsonEncode(run.toJson()),
      'seen_$dohaId': [for (final e in bundle.events) if (e.isDaily || e.isAffectionEvent || e.isEnding) e.id],
    });
    final container = await openDohaChat(tester, bundle: bundle);
    expect(container.read(chatRoomProvider(dohaId)).currentEventId, 'daily_weird_dream');
    await skipDailyTalks(tester);
    expect(container.read(chatRoomProvider(dohaId)).completedEventIds, contains('daily_weird_dream'));
    await settle(tester);
    // 공략 완료 패널의 '공략 후 이야기 열림' → 목록에서 본 이야기는 다시 보기
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    expect(notifier.epilogueItems.single.status, EpilogueStatus.seen);
    expect(find.byKey(const ValueKey('epilogue_button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('epilogue_button')));
    await settle(tester);
    final epilogue = find.byKey(const ValueKey('epilogue_daily_weird_dream'));
    await tester.scrollUntilVisible(epilogue, 200, scrollable: find.byType(Scrollable).last);
    expect(find.descendant(of: epilogue, matching: find.text('다시 보기')),
        findsOneWidget);
  });

  testWidgets('계속 무심하게 답하면 연락이 끊김', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    await choose(tester, '츄르 봉지를 흔들어 보라고 하기');
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '새벽부터 왜 깨우냐고 투정 부리기');
    await choose(tester, '토요일엔 선약이 있다고 거절하기');

    expect(state().progress, StoryProgress.stuck);
    expect(find.text('윤도하의 연락이 끊겼어요'), findsOneWidget);
    expect(find.text('처음부터 다시 하기'), findsOneWidget);
  });

  testWidgets('호감도 숫자는 화면에 나오지 않음', (tester) async {
    final container = await openChat(tester);
    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    expect(container.read(chatRoomProvider(dohaId)).internalAffection, 5);
    expect(find.textContaining('호감도'), findsNothing);
  });

  testWidgets('호감도 이벤트가 끝나면 지금 단계의 일상 대화가 하나 끼어듦', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    await tester.tap(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '다음엔 직접 두부 보러 가겠다고 하기'));
    await settle(tester);

    expect(state().currentEventId, 'daily_lunch_menu');
    expect(find.text('며칠 뒤 점심'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '돈까스라고 바로 답하기'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, '돈까스라고 바로 답하기'));
    await settle(tester);
    // 일상 대화가 끝나면 다음 호감도 이벤트로
    expect(state().completedEventIds, ['evt_dubu_missing', 'daily_lunch_menu']);
    expect(find.text('다음 날 새벽'), findsOneWidget);
  });

  testWidgets('자유대화에서 엔터로 보내도 입력창에 커서가 남아 연달아 칠 수 있음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester, roomId: freeRoomId(dohaId), extra: testAiOverrides);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '첫 번째');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(field.controller.text, isEmpty);

    await tester.enterText(find.byType(TextField), '두 번째');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    final sent = container
        .read(chatRoomProvider(freeRoomId(dohaId)))
        .messages
        .where((m) => m.isUser)
        .map((m) => m.text);
    expect(sent, containsAllInOrder(['첫 번째', '두 번째']));
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    await settle(tester);
  });

  testWidgets('자유대화가 꺼져 있으면 입력칸은 보이지만 못 쓰고, 선택지 대사는 입력칸에 쳐진 뒤 보내짐', (tester) async {
    final container = await openChat(tester);
    expect(find.byKey(const ValueKey('locked_input')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final send = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send_rounded));
    expect(send.onPressed, isNull);

    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    final before = container.read(chatRoomProvider(dohaId)).messages.where((m) => m.isUser).length;
    // 입력칸에 글자가 늘어나는 동안에는 아직 말풍선이 안 올라감
    final drafts = <String>[];
    int? sentWhileFirstDraft;
    container.listen<ChatRoomState>(chatRoomProvider(dohaId), (_, next) {
      if (next.userDraft.isNotEmpty) {
        drafts.add(next.userDraft);
        sentWhileFirstDraft ??= next.messages.where((m) => m.isUser).length;
      }
    });
    notifier.selectChoice(container.read(chatRoomProvider(dohaId)).currentChoices.first);
    for (var i = 0; i < 20 && drafts.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(drafts, isNotEmpty);
    expect(sentWhileFirstDraft, before);
    await tester.pump(const Duration(milliseconds: 20));
    if (container.read(chatRoomProvider(dohaId)).userDraft.isNotEmpty) {
      expect(find.byKey(const ValueKey('locked_input')), findsOneWidget);
    }

    await settle(tester);
    final after = container.read(chatRoomProvider(dohaId));
    expect(after.userDraft, isEmpty);
    expect(after.messages.where((m) => m.isUser).length, greaterThan(before));
  });

  testWidgets('특별 이벤트: 그 시간에 대화방에 있으면 한 번만 오고, 다시 해도 또 오지 않음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(
      tester,
      extra: [clockProvider.overrideWithValue(() => DateTime(2026, 10, 23, 1, 30))],
    );
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    // 첫 대화는 시간과 상관없이 첫 이벤트부터
    expect(state().currentEventId, 'evt_dubu_missing');
    await tester.tap(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '다음엔 직접 두부 보러 가겠다고 하기'));
    await settle(tester);

    // 새벽 1시 반 → 새벽에만 오는 톡이 먼저 (장면 전환 문구 없이)
    expect(state().currentEventId, 'special_playlist');
    expect(find.text('안 자?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '내일 들어본다고 하기'));
    await settle(tester);
    // 끝나면 원래 흐름(일상 대화)으로, 특별 이벤트는 공략 목록에 안 들어감
    expect(state().currentEventId, 'daily_lunch_menu');
    expect(state().completedEventIds, ['evt_dubu_missing']);

    container.read(chatRoomProvider(dohaId).notifier).restart();
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '다음엔 직접 두부 보러 가겠다고 하기'));
    await settle(tester);
    expect(state().currentEventId, 'daily_lunch_menu');
  });

  testWidgets('공략 뒤 다시 보기에서 그 시간에 못 받은 특별한 톡도 볼 수 있음', (tester) async {
    final bundle = loadSampleBundle();
    final run = SavedRun(
      affection: 100,
      flags: const [],
      completedEventIds: [
        for (final e in bundle.events)
          if (e.isAffectionEvent || e.isDaily || e.isEnding) e.id,
      ],
      messages: const [],
      cleared: true,
    );
    SharedPreferences.setMockInitialValues({...fastTempo, 'run_$dohaId': jsonEncode(run.toJson())});
    final container = await openDohaChat(tester, bundle: bundle);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    final notifier = container.read(chatRoomProvider(dohaId).notifier);

    final special = notifier.replayableEvents.firstWhere((r) => r.event.id == 'special_playlist');
    expect(special.missed, isTrue);
    expect(notifier.replayableEvents.last.event.isSpecial, isTrue, reason: '특별한 톡은 이야기 뒤에');
    final completed = state().completedEventIds;

    await tester.tap(find.byKey(const ValueKey('replay_button')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final item = find.byKey(const ValueKey('replay_special_playlist'));
    await tester.scrollUntilVisible(item, 200, scrollable: find.byType(Scrollable).last);
    expect(find.descendant(of: item, matching: find.textContaining('아직 못 받음')), findsOneWidget);
    await tester.tap(item);
    await settle(tester);
    expect(state().isReplaying, isTrue);
    expect(find.text('안 자?'), findsOneWidget);
    while (state().currentChoices.isNotEmpty) {
      await tester.tap(find.widgetWithText(ElevatedButton, state().currentChoices.first.buttonLabel));
      await settle(tester);
    }
    expect(state().isReplaying, isFalse);
    expect(state().progress, StoryProgress.cleared);
    expect(state().completedEventIds, completed);
    expect(find.text('다시 보기가 끝났어요'), findsOneWidget);
    // 받은 뒤엔 '못 받음'이 아니고, 안 고른 선택지가 남았을 때만 목록에 남음
    final again = notifier.replayableEvents.where((r) => r.event.id == 'special_playlist');
    expect(again.every((r) => !r.missed && r.unseenChoices > 0), isTrue);
  });

  testWidgets('스토리 방엔 자유대화 스위치가 없고, 자유대화 방은 따로 저장되며 호감도가 없음', (tester) async {
    final story = await openChat(tester);
    expect(find.byType(Switch), findsNothing);
    final storyAffection = story.read(chatRoomProvider(dohaId)).internalAffection;
    await settle(tester);

    final container = await openDohaChat(tester, roomId: freeRoomId(dohaId), extra: testAiOverrides);
    final room = freeRoomId(dohaId);
    expect(find.byKey(const ValueKey('free_room_intro')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_ai_pill')), findsOneWidget);
    expect(container.read(chatRoomProvider(room)).currentChoices, isEmpty);

    await tester.enterText(find.byType(TextField), '안녕 뭐해');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
    final free = container.read(chatRoomProvider(room));
    expect(free.messages.where((m) => m.isUser).map((m) => m.text), contains('안녕 뭐해'));
    expect(free.internalAffection, storyAffection, reason: '자유대화 방은 호감도가 변하지 않음');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('run_$room'), contains('안녕 뭐해'));
    expect(prefs.getString('run_$dohaId') ?? '', isNot(contains('안녕 뭐해')), reason: '스토리 방과 따로 저장');

    // 새로 열어도 자유대화 방 대화는 그대로
    await openDohaChat(tester, roomId: room);
    expect(find.text('안녕 뭐해'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('공략 뒤 못 본 일상 대화가 이어서 나옴', (tester) async {
    final bundle = loadSampleBundle();
    final all = [
      for (final e in bundle.events)
        if (e.isAffectionEvent || e.isDaily || e.isEnding) e.id,
    ];
    final run = SavedRun(
      affection: 100,
      flags: const [],
      completedEventIds: [for (final id in all) if (id != 'daily_rain') id],
      messages: const [],
      cleared: true,
    );
    SharedPreferences.setMockInitialValues({...fastTempo, 'run_$dohaId': jsonEncode(run.toJson())});
    final container = await openDohaChat(tester, bundle: bundle);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    expect(state().progress, StoryProgress.cleared);
    expect(state().currentEventId, 'daily_rain');
    expect(await skipDailyTalks(tester), ['daily_rain']);
    await settle(tester);
  });

  testWidgets('공략 뒤 대화가 이어지는 동안엔 말풍선 사이에 공략 완료 패널이 안 뜸', (tester) async {
    final bundle = loadSampleBundle();
    final all = [
      for (final e in bundle.events)
        if (e.isAffectionEvent || e.isDaily || e.isEnding) e.id,
    ];
    final run = SavedRun(
      affection: 100,
      flags: const [],
      completedEventIds: [for (final id in all) if (id != 'daily_rain') id],
      messages: const [],
      cleared: true,
    );
    SharedPreferences.setMockInitialValues({...fastTempo, 'run_$dohaId': jsonEncode(run.toJson())});
    // 방에 들어오는 첫 화면부터 잘게 넘기며 봄
    final container = await openDohaChat(tester, bundle: bundle, settleAfter: false);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    final panel = find.textContaining('처음부터 다시 하기');

    // 대화가 끝날 때까지, 들어오자마자 포함 패널이 한 번도 안 보여야 함
    for (var i = 0; i < 800; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ChatScreen).evaluate().isEmpty) continue;
      final s = state();
      if (s.currentChoices.isNotEmpty) {
        expect(panel, findsNothing);
        await tester.tap(find.widgetWithText(ElevatedButton, s.currentChoices.first.buttonLabel));
        continue;
      }
      if (!s.isScriptPlaying) break;
      expect(panel, findsNothing, reason: '대화 도중 말풍선 사이에 패널이 뜸');
    }
    expect(state().isScriptPlaying, isFalse);
    expect(state().completedEventIds, contains('daily_rain'));
    await tester.pump();
    expect(panel, findsOneWidget);
  });

  testWidgets('대화가 끝나면 바로 다음 장면으로 안 넘어가고, 쉬었다가 시간 표시 → 또 잠깐 뒤 첫 톡', (tester) async {
    // 보통 대화 속도(1배)
    SharedPreferences.setMockInitialValues({...fastTempo, 'tempo_$dohaId': '1.0'});
    final container = await openDohaChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    const tempo = 1.0;

    var elapsed = Duration.zero;
    Duration? ended, noticed, firstTalk;
    final doneBefore = state().completedEventIds.length;
    var messagesAtNotice = 0;
    container.listen<ChatRoomState>(chatRoomProvider(dohaId), (_, next) {
      if (ended == null && next.completedEventIds.length > doneBefore) ended = elapsed;
      if (ended != null && noticed == null && next.messages.lastOrNull?.isSystem == true) {
        noticed = elapsed;
        messagesAtNotice = next.messages.length;
      }
      if (noticed != null && firstTalk == null && next.messages.length > messagesAtNotice) firstTalk = elapsed;
    });

    for (var i = 0; i < 6 && ended == null; i++) {
      final choices = state().currentChoices;
      if (choices.isNotEmpty) notifier.selectChoice(choices.first);
      for (var j = 0; j < 2000 && state().currentChoices.isEmpty && ended == null; j++) {
        await tester.pump(const Duration(milliseconds: 50));
        elapsed += const Duration(milliseconds: 50);
      }
    }
    for (var j = 0; j < 2000 && firstTalk == null; j++) {
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
    }
    expect(ended, isNotNull);
    expect(noticed, isNotNull);
    expect(noticed! - ended!, greaterThanOrEqualTo(ChatRoomNotifier.sceneGapBefore * tempo));
    expect(firstTalk! - noticed!, greaterThanOrEqualTo(ChatRoomNotifier.sceneGapAfter * tempo));
    await settle(tester);
  });
}
