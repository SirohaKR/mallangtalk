import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/features/settings/byok_settings.dart';

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

/// 공략·스크립트를 다 본 것처럼 자유대화를 열어 둠
const freeTalkOpen = {'freetalk_$dohaId': '1'};

// Explicit AI configuration for tests about sending/keyboard behavior.
// Missing-key tests intentionally do not install these overrides.
List<Override> get testAiOverrides => [
      byokSettingsProvider.overrideWith(_TestAiSettings.new),
      claudeChatClientProvider.overrideWithValue(
          ClaudeChatClient(dio: Dio()..httpClientAdapter = _TestAiAdapter())),
    ];

class _TestAiSettings extends ByokSettingsNotifier {
  @override
  ByokSettings build() =>
      const ByokSettings(apiKey: 'test-key', model: 'test-model');
}

class _TestAiAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancel) async =>
      ResponseBody.fromString(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'replies': ['테스트 답장'],
                  'affection_delta': 0
                })
              }
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

ScenarioBundle loadSampleBundle() => ScenarioBundle.fromJson(
      jsonDecode(File('test/fixtures/sample_character.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// 앱의 로딩 문지기와 같은 역할: 기본 캐릭터와 저장소가 준비되면 윤도하 대화방을 띄움
class BootGate extends ConsumerWidget {
  const BootGate({super.key, this.roomId = dohaId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(builtinBundlesProvider).hasValue &&
        ref.watch(sharedPreferencesProvider).hasValue;
    return ready
        ? ChatScreen(roomId: roomId)
        : const Scaffold(body: SizedBox());
  }
}

/// 테스트 시각: 오후 3시 (밤·새벽에만 오는 특별 이벤트가 끼어들지 않게)
DateTime testNow() => DateTime(2026, 10, 22, 15);

/// 윤도하 대화방을 연 앱 (새 ProviderScope = 새로고침한 것과 같음)
Future<ProviderContainer> openDohaChat(
  WidgetTester tester, {
  List<Override> extra = const [],
  ScenarioBundle? bundle,
  String roomId = dohaId,
}) async {
  bundle ??= loadSampleBundle();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [bundle!]),
        sharedPreferencesProvider
            .overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
        storyRandomProvider.overrideWithValue(FirstPick()),
        ...extra,
      ],
      child: MaterialApp(
          theme: AppTheme.lightTheme, home: BootGate(roomId: roomId)),
    ),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
}

/// 일상 대화를 무작위 대신 늘 첫 번째로 고르는 주사위 (테스트 흐름 고정용)
class FirstPick implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
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
    if (eventId == null ||
        !eventId.startsWith('daily_') ||
        state.currentChoices.isEmpty) break;
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
