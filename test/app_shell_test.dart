import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/studio/template_scenario.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 하단 탭(내 캐릭터 / 채팅 / 캐릭터 추가 / 설정)이 있는 실제 앱 화면 흐름 테스트입니다.
void main() {
  ScenarioBundle loadIjun() => ScenarioBundle.fromJson(
        jsonDecode(File('assets/scenarios/example_seo_ijun.json').readAsStringSync())
            as Map<String, dynamic>,
      );

  testWidgets('채팅 탭에서 안 읽은 톡을 보고, 대화방에 들어가면 읽음 처리', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'chat_rooms_v1': [dohaId],
    });
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

    // 처음 화면은 내 캐릭터 탭, 기본 캐릭터 윤도하가 있음
    expect(find.text('내 캐릭터 1'), findsOneWidget);
    expect(find.text('윤도하'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final room = container.read(chatRoomProvider(dohaId));
    // 대화방을 안 열어도 톡은 와 있고(안 읽음), 말풍선이 두 번씩 쌓이지 않음
    final texts = room.messages.where((m) => !m.isSystem).map((m) => m.text).toList();
    // 대본의 {이름} 자리에 이 대화의 내 별명이 들어감
    expect(texts.first, '쨋뀨야 야야야');
    expect(texts.toSet().length, texts.length, reason: texts.join(' / '));
    expect(room.unreadCount, texts.length);

    await tester.tap(find.text('채팅'));
    await settle(tester);
    expect(find.text('${room.unreadCount}'), findsWidgets);

    await tester.tap(find.text('윤도하'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).unreadCount, 0);
    expect(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'), findsOneWidget);

    await tester.tap(find.byTooltip('채팅방 목록'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);

    await tester.tap(find.text('캐릭터 추가'));
    await settle(tester);
    expect(find.text('받아오기'), findsOneWidget);
    expect(find.text('친구'), findsWidgets); // 이미 친구인 윤도하 카드에 배지
  });

  testWidgets('갤러리에서 상세를 보고 친구 추가, 처음 대화는 기본 별명으로 시작하되 바꿀 수 있음', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tempo_char_example_seo_ijun': '0.2',
      'my_profile': jsonEncode({'nickname': '말랑', 'intro': ''}),
    });
    appRouter.go('/friends'); // 앞 테스트에서 옮겨 간 탭 위치 초기화
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle(), loadIjun()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
    expect(find.text('내 캐릭터 1'), findsOneWidget);

    await tester.tap(find.text('캐릭터 추가'));
    await settle(tester);
    expect(find.text('말수 적은 사진 동아리 선배가 자꾸 출사에 부른다'), findsOneWidget);
    await tester.tap(find.text('서이준'));
    await settle(tester);

    // 상세: 캐릭터 정보·캐릭터 설정·세계관 설정·나는 이 이야기에서·주변 인물만, 비밀과 제작용 정보는 안 보임
    for (final title in ['캐릭터 정보', '캐릭터 설정', '세계관 설정', '나는 이 이야기에서', '주변 인물']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('시각디자인과 4학년'), findsOneWidget);
    expect(find.textContaining('대학 사진 동아리'), findsOneWidget);
    expect(find.text('말랑 · 사진 동아리에 새로 들어온 후배'), findsOneWidget);
    expect(find.textContaining('몰래 저장해 둠'), findsNothing);
    for (final hidden in ['관계 단계', '이야기 분량', '타자 스타일', '성격', '찍을 거 없으면 너라도 찍지 뭐.']) {
      expect(find.textContaining(hidden), findsNothing, reason: hidden);
    }

    await tester.tap(find.text('친구 추가'));
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(characterLibraryProvider).map((e) => e.id),
        contains('char_example_seo_ijun'));
    // 친구가 되기 전엔 톡이 오지 않음 (별명을 정하고 대화를 시작해야 함)
    expect(container.read(chatRoomProvider('char_example_seo_ijun')).messages, isEmpty);

    await tester.tap(find.text('친구 · 1:1 채팅'));
    await settle(tester);
    expect(find.text('서이준과 대화 시작'), findsOneWidget);
    expect(find.widgetWithText(TextField, '말랑'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '후배님');
    await tester.tap(find.text('대화 시작'));
    await settle(tester);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('후배님.'), findsOneWidget);
    expect(container.read(chatRoomsProvider), contains('char_example_seo_ijun'));
  });

  testWidgets('만들기: 예시를 불러와 대사 탭에서 고치고 저장하면 내 캐릭터에 생김', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/add');
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
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();
    expect(find.text('호감도 단계'), findsOneWidget);

    await tester.tap(find.byTooltip('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예시 캐릭터 불러오기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('불러오기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '서이준'), findsOneWidget);

    // 캐릭터 탭은 한 항목씩 화살표로 넘김: 기본 정보 → 캐릭터 정보 → 캐릭터 설정(넓은 칸 + 글자 수)
    expect(find.text('1/8'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2/8'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '시각디자인과 4학년'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('3/8'), findsOneWidget);
    final setting = templateScenario().character.worldviewPrompt;
    expect(find.text('${setting.characters.length}자'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, setting), '$setting 커피는 늘 블랙.');
    await tester.pump();
    expect(find.text('${setting.characters.length + 10}자'), findsOneWidget);

    // 대사 탭: 첫 대화의 첫 말풍선을 고침
    await tester.tap(find.text('대사'));
    await tester.pumpAndSettle();
    expect(find.text('장면 1'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '내일 출사 가는데.'), '내일 출사 가는데 같이 갈래.');
    await tester.pump();

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final entries = container.read(characterLibraryProvider);
    expect(entries, hasLength(2));
    final made = entries.last;
    expect(made.source, CharacterSource.created);
    expect(made.bundle.character.name, '서이준');
    expect(made.bundle.events, hasLength(5));
    final first = made.bundle.firstNodeOf(made.bundle.events.first.id)!;
    expect(first.characterBubbles.map((b) => b.text), contains('내일 출사 가는데 같이 갈래.'));
    expect(made.bundle.character.worldviewPrompt, endsWith('커피는 늘 블랙.'));
    // 저장하면 새 캐릭터를 만들 수 있게 빈 칸으로 돌아감
    expect(find.widgetWithText(TextFormField, '서이준'), findsNothing);
  });
}
