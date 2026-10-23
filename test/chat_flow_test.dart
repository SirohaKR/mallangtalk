import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 샘플 시나리오(윤도하)를 실제 화면에서 끝까지 플레이해 보는 테스트입니다.
void main() {
  Future<ProviderContainer> openChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    return openDohaChat(tester);
  }

  testWidgets('모든 컷씬을 모으면 엔딩 후 공략 완료', (tester) async {
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
    expect(find.text('처음부터 다시 하기'), findsOneWidget);
  });

  testWidgets('공연을 거절하면 컷씬을 놓치고, 다시 하기로 모으면 이미 본 컷씬은 인정됨', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    await choose(tester, '츄르 봉지를 흔들어 보라고 하기');
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '다음엔 나도 같이 뛰자고 하기');
    await choose(tester, '토요일엔 선약이 있다고 거절하기');
    expect(state().unlockedCutsceneEventIds, isNot(contains('evt_gig_tickets')));
    await choose(tester, '누가 봐도 하트라고 해주기');
    await choose(tester, '2분 뒤에 뭐가 있냐고 묻기');
    await choose(tester, '들어보고 울컥했다고 말하기');
    await choose(tester, '모르는 척하기');
    await choose(tester, '장난이었다고 사과하기');
    await choose(tester, '지금 간다고 하기');

    expect(state().progress, StoryProgress.missedCutscenes);
    expect(container.read(chatRoomProvider(dohaId).notifier).missedCutsceneCount, 1);
    expect(find.text('그날 늦은 밤'), findsNothing);

    await tester.tap(find.text('처음부터 다시 하기'));
    await settle(tester);
    expect(state().progress, StoryProgress.playing);
    expect(state().unlockedCutsceneEventIds, hasLength(3));

    await choose(tester, '침대 밑이랑 좁은 곳부터 찾아보라고 하기');
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '방금 일어났다고, 사진 예쁘다고 답하기');
    await choose(tester, '좋다고, 무슨 밴드냐고 묻기');
    await choose(tester, '벌써 기대된다고 하기');
    await choose(tester, '감자 같다고 놀리기');
    await choose(tester, '내 생일 기억한 거냐고 묻기');
    await choose(tester, '들어보고 울컥했다고 말하기');
    await choose(tester, '우리 처음 만난 날이라고 답하기');
    await choose(tester, '뭐가 그날부터냐고 묻기');
    await choose(tester, '지금 간다고 하기');
    await choose(tester, '좋다고 대답하기');
    expect(state().progress, StoryProgress.cleared);
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
    SharedPreferences.setMockInitialValues({...fastTempo, ...freeTalkOpen});
    final container = await openDohaChat(tester);
    container.read(chatRoomProvider(dohaId).notifier).toggleDirectInputMode(true);
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
        .read(chatRoomProvider(dohaId))
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

  testWidgets('자유대화는 처음엔 잠겨 있어서 켜려 해도 안 켜지고 안내만 나옴', (tester) async {
    final container = await openChat(tester);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    expect(container.read(chatRoomProvider(dohaId)).freeTalkUnlocked, isFalse);
    notifier.toggleDirectInputMode(true);
    expect(container.read(chatRoomProvider(dohaId)).isByokAiModeEnabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.textContaining('스크립트를 전부 보면 자유대화가 열려요'), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).isByokAiModeEnabled, isFalse);
    await settle(tester);
  });

  testWidgets('공략 뒤 못 본 일상 대화가 이어서 나오고, 다 보면 팝업과 함께 자유대화가 열림', (tester) async {
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
    expect(state().freeTalkUnlocked, isFalse);
    expect(state().currentEventId, 'daily_rain');
    expect(await skipDailyTalks(tester), ['daily_rain']);

    expect(find.text('스크립트를 전부 봤어요'), findsOneWidget);
    await tester.tap(find.text('좋아요'));
    await settle(tester);
    expect(find.text('스크립트를 전부 봤어요'), findsNothing);
    expect(state().freeTalkUnlocked, isTrue);

    container.read(chatRoomProvider(dohaId).notifier).toggleDirectInputMode(true);
    expect(state().isByokAiModeEnabled, isTrue);

    // 새로 열어도 열린 채로, 팝업은 다시 안 뜸
    await openDohaChat(tester, bundle: bundle);
    expect(dohaState(tester).freeTalkUnlocked, isTrue);
    expect(find.text('스크립트를 전부 봤어요'), findsNothing);
    await settle(tester);
  });
}
