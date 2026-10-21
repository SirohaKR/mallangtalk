import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/core/theme/app_theme.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 샘플 시나리오(윤도하)를 실제 화면에서 끝까지 플레이해 보는 테스트입니다.
void main() {
  final bundle = ScenarioBundle.fromJson(
    jsonDecode(File('assets/scenarios/sample_character.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  Future<ProviderContainer> openChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scenarioBundleProvider.overrideWith((ref) async => bundle),
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const BootGate()),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('모든 컷씬을 모으면 엔딩 후 공략 완료', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider);

    expect(state().isByokAiModeEnabled, isFalse);
    expect(find.text('토요일 오전 10:24'), findsOneWidget);

    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    // 2단계 대사가 끝나면 컷씬이 뜨고, 닫기 전까지는 선택지가 안 나옴
    expect(state().activeCutscene?.id, 'evt_dubu_missing');
    expect(state().currentChoices, isEmpty);
    await closeCutscene(tester);
    await choose(tester, '다음엔 직접 두부 보러 가겠다고 하기');

    expect(find.text('화요일 오전 6:40'), findsOneWidget);
    await choose(tester, '다음엔 나도 같이 뛰자고 하기');

    await choose(tester, '좋다고, 무슨 밴드냐고 묻기');
    expect(state().activeCutscene?.id, 'evt_gig_tickets');
    await closeCutscene(tester);
    await choose(tester, '근데 왜 하필 내 생각이 났냐고 묻기');

    await choose(tester, '다음에 나한테도 하나 만들어 달라고 하기');

    await choose(tester, '내 생일 기억한 거냐고 묻기');
    await closeCutscene(tester);
    await choose(tester, '1년 동안 받은 선물 중에 제일 좋다고 하기');

    await choose(tester, '우리 처음 만난 날이라고 답하기');
    await choose(tester, '나도 그날 기억난다고, USB 얘기 꺼내기');
    expect(state().activeCutscene?.id, 'evt_first_year');
    await closeCutscene(tester);
    await choose(tester, '지금 간다고 하기');

    expect(find.text('그날 밤 8:10'), findsOneWidget);
    await choose(tester, '좋다고 대답하기');
    expect(state().progress, StoryProgress.cleared);
    expect(state().unlockedCutsceneEventIds, hasLength(4));
    expect(find.text('윤도하 공략 완료'), findsOneWidget);
    expect(find.text('처음부터 다시 하기'), findsOneWidget);
  });

  testWidgets('공연을 거절하면 컷씬을 놓치고, 다시 하기로 모으면 이미 본 컷씬은 인정됨', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider);

    await choose(tester, '츄르 봉지를 흔들어 보라고 하기');
    await closeCutscene(tester);
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '다음엔 나도 같이 뛰자고 하기');
    await choose(tester, '토요일엔 선약이 있다고 거절하기');
    expect(state().activeCutscene, isNull);
    await choose(tester, '누가 봐도 하트라고 해주기');
    await choose(tester, '2분 뒤에 뭐가 있냐고 묻기');
    await closeCutscene(tester);
    await choose(tester, '들어보고 울컥했다고 말하기');
    await choose(tester, '모르는 척하기');
    await choose(tester, '장난이었다고 사과하기');
    await closeCutscene(tester);
    await choose(tester, '지금 간다고 하기');

    expect(state().progress, StoryProgress.missedCutscenes);
    expect(container.read(chatRoomProvider.notifier).missedCutsceneCount, 1);
    expect(find.text('그날 밤 8:10'), findsNothing);

    await tester.tap(find.text('처음부터 다시 하기'));
    await settle(tester);
    expect(state().progress, StoryProgress.playing);
    expect(state().unlockedCutsceneEventIds, hasLength(3));

    await choose(tester, '침대 밑이랑 좁은 곳부터 찾아보라고 하기');
    await closeCutscene(tester);
    await choose(tester, '두부 사진 더 보내달라고 조르기');
    await choose(tester, '방금 일어났다고, 사진 예쁘다고 답하기');
    await choose(tester, '좋다고, 무슨 밴드냐고 묻기');
    await closeCutscene(tester);
    await choose(tester, '벌써 기대된다고 하기');
    await choose(tester, '감자 같다고 놀리기');
    await choose(tester, '내 생일 기억한 거냐고 묻기');
    await closeCutscene(tester);
    await choose(tester, '들어보고 울컥했다고 말하기');
    await choose(tester, '우리 처음 만난 날이라고 답하기');
    await choose(tester, '뭐가 그날부터냐고 묻기');
    await closeCutscene(tester);
    await choose(tester, '지금 간다고 하기');
    await choose(tester, '좋다고 대답하기');
    expect(state().progress, StoryProgress.cleared);
  });

  testWidgets('계속 무심하게 답하면 연락이 끊김', (tester) async {
    final container = await openChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider);

    await choose(tester, '츄르 봉지를 흔들어 보라고 하기');
    await closeCutscene(tester);
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
    await closeCutscene(tester);
    expect(container.read(chatRoomProvider).internalAffection, 5);
    expect(find.textContaining('호감도'), findsNothing);
  });
}
