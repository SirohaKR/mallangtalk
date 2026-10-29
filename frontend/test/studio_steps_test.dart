import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/template_scenario.dart';
import 'test_helpers.dart';

/// 만들기 4단계 성격 막대, 7단계 AI로 생성하기 창, 8단계 캐릭터 사진함
void main() {
  // 1x1 PNG
  const png =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

  Future<void> openStudio(WidgetTester tester, ScenarioDraft draft, {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({'studio_draft_v1': jsonEncode(draft.toBundle().toJson()), ...prefs});
    appRouter.go('/create');
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
  }

  Future<ScenarioDraft> savedDraft(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4)); // 자동 저장
    final prefs = await SharedPreferences.getInstance();
    return ScenarioDraft.fromBundle(
        ScenarioBundle.fromJson(jsonDecode(prefs.getString('studio_draft_v1')!) as Map<String, dynamic>));
  }

  Future<void> close(WidgetTester tester) async {
    appRouter.go('/friends'); // 자동 저장 타이머 정리
    await settle(tester);
  }

  testWidgets('4단계: 성격 막대를 더하고 밀면 초안에 저장됨', (tester) async {
    final draft = ScenarioDraft.fromBundle(templateScenario())..traits = [];
    await openStudio(tester, draft);
    await tester.tap(find.byKey(const ValueKey('studio_step_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio_trait_add')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '무심함'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '다정함'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('trait_slider_0')), const Offset(60, 0));
    await tester.pumpAndSettle();

    final saved = await savedDraft(tester);
    expect(saved.traits.single.left, '무심함');
    expect(saved.traits.single.right, '다정함');
    expect(saved.traits.single.percent, greaterThan(50));
    await close(tester);
  });

  testWidgets('8단계 사진함: 사진에 설명을 달면 같은 설명의 사진 말풍선에 붙고, 감정을 고르면 자유대화용이 됨', (tester) async {
    final draft = ScenarioDraft.fromBundle(templateScenario())..addPhoto(png);
    final line = LineDraft(photo: '필름 카메라 셀카');
    draft.events.first.scenes.last.lines.add(line);
    await openStudio(tester, draft);
    await tester.tap(find.byKey(const ValueKey('studio_step_7')));
    await tester.pumpAndSettle();

    expect(find.textContaining('사진함'), findsWidgets);
    expect(find.text('1장 · 자유대화용 0장'), findsOneWidget);
    expect(find.text('안 씀'), findsOneWidget);

    final caption = find.byKey(ValueKey<Object>('photo_caption_${ScenarioDraft.imageId(png)}'));
    await tester.enterText(caption, '필름 카메라 셀카');
    await tester.pumpAndSettle();
    await tester.tap(find.text('설렘'));
    await tester.pumpAndSettle();
    expect(find.text('1장 · 자유대화용 1장'), findsOneWidget);

    final saved = await savedDraft(tester);
    final slot = saved.events.first.photoSlots.firstWhere((s) => s.label == '필름 카메라 셀카');
    expect(saved.sharedPhotoFor(slot), png);
    expect(saved.photoTriggers[png]?.mood, '설렘');

    // 스토리에만으로 바꾸면 자유대화에서는 안 보냄
    await tester.ensureVisible(find.text('스토리에만'));
    await tester.tap(find.text('스토리에만'));
    await tester.pumpAndSettle();
    expect(find.text('1장 · 자유대화용 0장'), findsOneWidget);
    expect(find.text('설렘'), findsNothing);
    await close(tester);
  });

  testWidgets('7단계 AI로 생성하기: 빈 대화만 / 전부 새로 / 골라서와 예상 호출 수를 보여 줌', (tester) async {
    final draft = ScenarioDraft.fromBundle(templateScenario());
    draft.events.add(EventDraft(id: draft.newEventId(), title: '빈 대화', stage: draft.stageNames.first));
    await openStudio(tester, draft, prefs: {
      'byok_provider': 'claude',
      'byok_claude_api_key': 'sk-ant-test-0000',
      'byok_claude_model': 'claude-sonnet-5-5',
    });
    await tester.tap(find.byKey(const ValueKey('studio_step_6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio_ai_generate')));
    await tester.pumpAndSettle();

    expect(find.text('비어 있는 대화만'), findsOneWidget);
    expect(find.textContaining('빈 대화 1개만 써요'), findsOneWidget);
    expect(find.textContaining('호출 1번'), findsOneWidget);
    expect(find.text('Claude Sonnet 5.5'), findsOneWidget);

    await tester.tap(find.text('골라서'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(draft.events.length));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ai_start'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('ai_pick_0')));
    await tester.tap(find.byKey(const ValueKey('ai_pick_1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('호출 2번'), findsOneWidget);

    await tester.tap(find.text('전부 새로'));
    await tester.pumpAndSettle();
    expect(find.text('단계마다 호감도 이벤트'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    Navigator.of(tester.element(find.text('전부 새로'))).pop();
    await tester.pumpAndSettle();
    await close(tester);
  });
}
