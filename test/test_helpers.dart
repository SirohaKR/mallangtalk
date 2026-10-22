import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/core/theme/app_theme.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dohaId = 'char_yoon_doha';

/// 테스트에서는 '입력 중' 연출을 빠르게 (대화방의 캐릭터별 대화 속도) + 별명을 정해 둔 상태
const fastTempo = {'tempo_$dohaId': '0.2', 'nickname_$dohaId': '쨋뀨'};

ScenarioBundle loadSampleBundle() => ScenarioBundle.fromJson(
      jsonDecode(File('assets/scenarios/sample_character.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// 앱의 로딩 문지기와 같은 역할: 기본 캐릭터와 저장소가 준비되면 윤도하 대화방을 띄움
class BootGate extends ConsumerWidget {
  const BootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(builtinBundlesProvider).hasValue &&
        ref.watch(sharedPreferencesProvider).hasValue;
    return ready ? const ChatScreen(characterId: dohaId) : const Scaffold(body: SizedBox());
  }
}

/// 윤도하 대화방을 연 앱 (새 ProviderScope = 새로고침한 것과 같음)
Future<ProviderContainer> openDohaChat(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  final bundle = loadSampleBundle();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [bundle]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        ...extra,
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const BootGate()),
    ),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
}

/// 타자 연출 타이머를 충분히 흘려보냄
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

ChatRoomState dohaState(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChatScreen)))
        .read(chatRoomProvider(dohaId));

/// 일상 대화가 나오면 호감도가 가장 덜 오르는 답을 골라 넘김 (이벤트 흐름 테스트가 일상 대화에 흔들리지 않게)
Future<List<String>> skipDailyTalks(WidgetTester tester) async {
  final seen = <String>[];
  for (var i = 0; i < 12; i++) {
    final state = dohaState(tester);
    final eventId = state.currentEventId;
    if (eventId == null || !eventId.startsWith('daily_') || state.currentChoices.isEmpty) break;
    seen.add(eventId);
    final calm = state.currentChoices
        .reduce((a, b) => b.affectionDelta < a.affectionDelta ? b : a);
    await tester.tap(find.widgetWithText(ElevatedButton, calm.buttonLabel));
    await settle(tester);
  }
  return seen;
}

Future<void> choose(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  expect(button, findsOneWidget, reason: '선택지 "$label"이 보여야 함');
  await tester.tap(button);
  await settle(tester);
  await skipDailyTalks(tester);
}
