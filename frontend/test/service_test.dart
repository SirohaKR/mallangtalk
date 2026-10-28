import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/service_messages.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 서비스 말랑이: 정해진 때 먼저 톡, 문구 목록·데이터 표, 한 번 더 뽑기
void main() {
  const table = ServiceConfig(
    mode: 'table',
    columns: ['띠', '운세'],
    rows: [
      ['쥐띠', '작은 친절이 큰 행운으로'],
      ['소띠', '미뤄 둔 일을 끝내기 좋은 날'],
      ['범띠', '새 사람에게서 힌트를 얻어요'],
    ],
    template: '{이름}! 오늘 {띠} 운세는… {운세}',
  );

  ScenarioBundle serviceBundle(ServiceConfig config) {
    final base = loadSampleBundle().character;
    return ScenarioBundle(
      character: CharacterModel.fromJson({
        ...base.toJson(),
        'kind': 'service',
        'service': config.toJson(),
        'affection_stages': [],
      }),
      events: const [],
      nodes: const {},
    );
  }

  test('보낼 시각: 지난 때부터 지금까지 요일·시각이 맞는 것만, 오래된 순', () {
    const config = ServiceConfig(times: ['08:00', '21:00']);
    final slots = dueServiceSlots(config, DateTime(2026, 10, 24, 9), DateTime(2026, 10, 26, 10));
    expect(slots, [
      DateTime(2026, 10, 24, 21),
      DateTime(2026, 10, 25, 8),
      DateTime(2026, 10, 25, 21),
      DateTime(2026, 10, 26, 8),
    ]);
    // 2026-10-26은 월요일: 주말만 보내면 그날은 없음
    const weekend = ServiceConfig(days: [6, 7], times: ['08:00']);
    expect(dueServiceSlots(weekend, DateTime(2026, 10, 24, 9), DateTime(2026, 10, 26, 10)), [DateTime(2026, 10, 25, 8)]);
    expect(serviceScheduleLabel(weekend), '주말 오전 8:00');
    expect(serviceScheduleLabel(config), '매일 오전 8:00, 오후 9:00');
  });

  test('데이터 표: 한 줄을 틀에 넣고, 한 바퀴 돌 때까지 같은 줄이 안 나옴', () {
    final used = <String>{};
    final texts = <String>[];
    for (var i = 0; i < 3; i++) {
      final msg = composeServiceMessage(table,
          userName: '다홍', charName: '콩떡', now: DateTime(2026, 10, 26), random: Random(i), used: used)!;
      used.add(msg.key);
      texts.add(msg.text);
    }
    expect(texts.toSet(), hasLength(3));
    expect(texts.first, startsWith('다홍! 오늘 '));
    expect(texts.any((t) => t.contains('범띠 운세는… 새 사람에게서 힌트를 얻어요')), isTrue);
  });

  test('엑셀·시트에서 복사한 표(탭)와 CSV(쉼표)를 읽음', () {
    final tab = parseServiceTable('띠\t운세\n쥐띠\t좋은 날\n\n소띠\t쉬는 날\n');
    expect(tab.columns, ['띠', '운세']);
    expect(tab.rows, [
      ['쥐띠', '좋은 날'],
      ['소띠', '쉬는 날'],
    ]);
    expect(parseServiceTable('a,b\n1,2').rows.single, ['1', '2']);
  });

  test('서비스 말랑이는 초안을 거쳐도 그대로, 이야기·호감도 단계 없이 저장됨', () {
    final draft = ScenarioDraft.blank()
      ..name = '콩떡'
      ..kind = 'service'
      ..service = const ServiceConfig(mode: 'list', lines: ['']);
    expect(draft.problems(), contains('[보내기] 보낼 문구를 하나 이상 적어 주세요.'));
    draft.service = table;
    expect(draft.problems(), isEmpty);
    final bundle = ScenarioBundle.fromJson(jsonDecode(jsonEncode(draft.toBundle().toJson())) as Map<String, dynamic>);
    expect(bundle.character.isService, isTrue);
    expect(bundle.character.service!.rows, hasLength(3));
    expect(bundle.events, isEmpty);
    expect(bundle.character.affectionStages, isEmpty);
    final back = ScenarioDraft.fromBundle(bundle);
    expect(back.isService, isTrue);
    expect(back.service.template, table.template);
  });

  testWidgets('처음 대화방이 생기면 바로 한 통, 안 연 동안 지난 시각 톡은 쌓이고, 한 번 더 뽑기로 또 옴', (tester) async {
    const config = ServiceConfig(mode: 'list', lines: ['오늘도 좋은 하루!', '물 한 잔 마셔요', '{이름} 화이팅'], times: ['08:00']);
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester, bundle: serviceBundle(config));
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));
    expect(state().messages.where((m) => !m.isUser && !m.isSystem), hasLength(1));
    expect(state().internalAffection, 100);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('서비스'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('service_reroll')));
    await settle(tester);
    final texts = state().messages.where((m) => !m.isUser && !m.isSystem).map((m) => m.text).toList();
    expect(texts, hasLength(2));
    expect(texts.toSet(), hasLength(2), reason: '한 바퀴 돌 때까지 같은 문구 안 나옴');

    // 이틀 전에 마지막으로 받았으면, 그 뒤 오전 8시 톡들이 그 시각으로 쌓임 (테스트 시각 10월 22일 오후 3시)
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'svc_$dohaId': jsonEncode({'last': DateTime(2026, 10, 20, 9).millisecondsSinceEpoch, 'used': []}),
    });
    final again = await openDohaChat(tester, bundle: serviceBundle(config));
    final stacked = again.read(chatRoomProvider(dohaId)).messages.where((m) => !m.isUser && !m.isSystem).toList();
    expect(stacked.map((m) => m.timestamp), [DateTime(2026, 10, 21, 8), DateTime(2026, 10, 22, 8)]);
    expect(again.read(chatRoomProvider(dohaId)).unreadCount, 0, reason: '보고 있는 대화방이라 바로 읽음');
    await settle(tester);
  });
}
