import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/help/help_guide.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/settings/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 처음 사용자 도움말: 인사 → 프로필 → AI 키 → 말랑이 찾기 → 대화방, 만들기 안내, 설정에서 다시 보기
void main() {
  setUp(() => HelpGuide.autoShow = true);
  tearDown(() => HelpGuide.autoShow = false);

  Future<ProviderContainer> openApp(WidgetTester tester, String path, {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    appRouter.go(path);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => []),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(Navigator).first));
  }

  Future<List<String>> savedSeen() async =>
      ((await SharedPreferences.getInstance()).getString('help_seen') ?? '').split(',');

  testWidgets('처음 켜면 인사 → 내 프로필 → AI 키, 마치면 말랑이 찾기 화면 안내가 이어짐', (tester) async {
    final container = await openApp(tester, '/discover');
    expect(find.text('안녕! 나는 말랑이야'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome_start')));
    await settle(tester);

    // 프로필: 별명을 적으면 설정의 내 프로필에 저장
    expect(find.textContaining('뭐라고 부르면 좋을까'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('welcome_nickname')), '다홍');
    await tester.tap(find.byKey(const ValueKey('welcome_next')));
    await settle(tester);
    expect(container.read(userProfileProvider).nickname, '다홍');

    // AI 키: 지금은 건너뜀
    expect(find.textContaining('AI 키'), findsWidgets);
    expect(find.byKey(const ValueKey('welcome_ai_gemini')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome_later')));
    await settle(tester);

    // 말랑이 찾기 화면 위 안내 (점 다섯 개 중 세 번째)
    expect(find.byKey(const ValueKey('help_coach')), findsOneWidget);
    expect(find.textContaining('마음에 드는 카드를 눌러 봐'), findsOneWidget);
    expect(find.bySemanticsLabel('5단계 중 3단계'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help_done')));
    await settle(tester);
    expect(find.byKey(const ValueKey('help_coach')), findsNothing);
    expect(await savedSeen(), containsAll([HelpGuide.welcome, HelpGuide.discover]));

    // 다시 열어도 안 뜸
    await openApp(tester, '/discover', prefs: {
      'help_seen': (await savedSeen()).join(','),
      'my_profile': jsonEncode({'nickname': '다홍'}),
    });
    expect(find.text('안녕! 나는 말랑이야'), findsNothing);
    expect(find.byKey(const ValueKey('help_coach')), findsNothing);
  });

  testWidgets("'혼자 둘러볼게요'를 누르면 처음 안내 전체를 본 걸로 침", (tester) async {
    await openApp(tester, '/discover');
    await tester.tap(find.byKey(const ValueKey('welcome_alone')));
    await settle(tester);
    expect(find.byKey(const ValueKey('help_coach')), findsNothing);
    expect(await savedSeen(), containsAll(HelpGuide.tour));
  });

  testWidgets('이미 쓰던 사람은 인사 없이 화면 안내만, 내 말랑이 만들기로 가면 만들기 안내 고르기', (tester) async {
    await openApp(tester, '/discover', prefs: {'my_profile': jsonEncode({'nickname': '쨋뀨'})});
    expect(find.text('안녕! 나는 말랑이야'), findsNothing);
    expect(find.byKey(const ValueKey('help_coach')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help_coach_extra')));
    await settle(tester);

    // 만들기 첫 화면에서 안내 고르기 → AI로 만들기 안내 (지금 단계 이름)
    expect(find.byKey(const ValueKey('create_help_sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help_pick_${HelpGuide.createAi}')));
    await settle(tester);
    expect(find.textContaining('7단계 호감도·대본'), findsOneWidget);
    expect(find.textContaining('9단계 공개'), findsOneWidget);
    expect(find.byKey(const ValueKey('help_guide_key')), findsOneWidget); // 키가 없으면 바로 연결
    await tester.tap(find.byKey(const ValueKey('help_guide_back')));
    await settle(tester);
    expect(find.text('봤어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create_help_close')));
    await settle(tester);
    expect(await savedSeen(), containsAll([HelpGuide.discover, HelpGuide.create, HelpGuide.createAi]));

    // '?' 버튼으로 다시
    await tester.tap(find.byKey(const ValueKey('studio_help')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('help_pick_${HelpGuide.createService}')));
    await settle(tester);
    expect(find.textContaining('읽씹 / 정해 둔 답 / AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help_guide_ok')));
    await settle(tester);
    expect(find.byKey(const ValueKey('help_guide_${HelpGuide.createService}')), findsNothing);
    appRouter.go('/my');
    await settle(tester);
  });

  testWidgets('대화방 안내: 다시 보지 않기를 끄면 다음에 또 뜨고, 켜 두면 안 뜸', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, 'help_seen': 'welcome,discover,start'});
    await openDohaChat(tester);
    expect(find.text('대화방은 이렇게 생겼어!'), findsOneWidget);
    expect(find.textContaining('말랑이가 차오르는 걸'), findsOneWidget);
    expect(find.byType(HelpPin), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('help_never_again')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('help_done')));
    await settle(tester);
    expect(await savedSeen(), isNot(contains(HelpGuide.room)));

    SharedPreferences.setMockInitialValues({...fastTempo, 'help_seen': 'welcome,discover,start'});
    await openDohaChat(tester);
    expect(find.text('대화방은 이렇게 생겼어!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help_done')));
    await settle(tester);
    expect(await savedSeen(), contains(HelpGuide.room));
  });

  testWidgets('설정 › 도움말 다시 보기: 화면 안내 다시 켜기', (tester) async {
    final container = await openApp(tester, '/settings', prefs: {
      'my_profile': jsonEncode({'nickname': '쨋뀨'}),
      'help_seen': HelpGuide.tour.join(','),
    });
    expect(find.byKey(const ValueKey('help_coach')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings_help')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('help_again_reset')));
    await tester.pumpAndSettle();
    expect(container.read(helpSeenProvider), isEmpty);
    expect(find.textContaining('화면 안내를 다시 켰어요'), findsOneWidget);
    // 본 안내는 계정 연동 값
    expect(LocalStore.isSyncedKey('help_seen'), isTrue);
  });
}
