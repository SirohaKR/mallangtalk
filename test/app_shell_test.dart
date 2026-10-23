import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/network/ai_provider.dart';
import 'package:mallangtalk/core/network/server_info.dart';
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

  testWidgets('친구 탭: 맨 위 내 프로필, 별을 누르면 즐겨찾기로 올라감', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, 'my_profile': '{"nickname":"쨋뀨","intro":"고양이 좋아함"}'});
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
    expect(find.text('쨋뀨'), findsOneWidget);
    expect(find.text('고양이 좋아함'), findsOneWidget);
    expect(find.text('즐겨찾기 1'), findsNothing);

    await tester.tap(find.text('윤도하'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('즐겨찾기'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byTooltip('즐겨찾기 빼기'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('즐겨찾기 1'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorites_v1'), [dohaId]);
  });

  testWidgets('대화방 위 캐릭터 사진을 누르면 프로필, 1:1 채팅은 시트만 닫고 대화방은 그대로', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, 'chat_rooms_v1': [dohaId]});
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
    appRouter.go('/chat/$dohaId');
    await settle(tester);

    await tester.tap(find.byTooltip('프로필 보기'));
    await tester.pumpAndSettle();
    expect(find.text('캐릭터 파일'), findsOneWidget);
    // 프로필 사진을 누르면 크게, 누르면 다시 닫힘
    await tester.tap(find.byKey(const ValueKey('profile_photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo_viewer')), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo_viewer')), findsNothing);
    await tester.tap(find.text('1:1 채팅'));
    await tester.pumpAndSettle();
    expect(find.text('캐릭터 파일'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    appRouter.go('/friends');
    await settle(tester);
  });

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
    expect(find.text('친구 1'), findsOneWidget);
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
    expect(find.text('친구 1'), findsOneWidget);

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

  testWidgets('내 캐릭터 프로필에서 1:1 채팅을 누르면 별명을 정하고 대화방으로 이동', (tester) async {
    SharedPreferences.setMockInitialValues({'tempo_$dohaId': '0.2'});
    appRouter.go('/friends');
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

    // 처음: 프로필 시트가 닫힌 뒤에도 별명 창이 뜨고, 정하면 대화방이 열림
    await tester.tap(find.text('윤도하'));
    await settle(tester);
    await tester.tap(find.text('1:1 채팅'));
    await settle(tester);
    expect(find.text('윤도하와 대화 시작'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '말랑');
    await tester.tap(find.text('대화 시작'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);

    // 두 번째: 별명이 이미 있으면 바로 대화방
    appRouter.go('/friends');
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);
    await tester.tap(find.text('윤도하'));
    await settle(tester);
    await tester.tap(find.text('1:1 채팅'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);

    // 프로필 시트의 대화 속도도 시트가 닫힌 뒤 제대로 열림
    appRouter.go('/friends');
    await settle(tester);
    await tester.tap(find.text('윤도하'));
    await settle(tester);
    await tester.tap(find.text('대화 속도'));
    await settle(tester);
    expect(find.text('윤도하 대화 속도'), findsOneWidget);
  });

  testWidgets('설정: 드롭다운으로 AI 회사를 고르고 키와 모델을 저장', (tester) async {
    SharedPreferences.setMockInitialValues({'byok_claude_api_key': 'sk-ant-old-key-123456'});
    appRouter.go('/settings');
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.textContaining('저장된 키'), findsOneWidget);

    await tester.tap(find.text('Claude (Anthropic)'));
    await settle(tester);
    await tester.tap(find.text('Gemini (Google)').last);
    await settle(tester);
    expect(find.textContaining('저장된 키'), findsNothing); // Gemini 키는 아직 없음
    await tester.enterText(find.widgetWithText(TextField, 'AIza로 시작하는 Gemini API 키'), 'AIza-new-key-0000');

    await tester.tap(find.textContaining('Gemini 3.8 Flash')); // Gemini는 무료 한도가 있는 Flash가 기본
    await settle(tester);
    await tester.tap(find.textContaining('Gemini 3.5 Flash-Lite').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('byok_provider'), 'gemini');
    expect(prefs.getString('byok_key_gemini'), 'AIza-new-key-0000');
    expect(prefs.getString('byok_model_gemini'), 'gemini-3.5-flash-lite');
    expect(prefs.getString('byok_claude_api_key'), 'sk-ant-old-key-123456'); // Claude 키는 그대로
  });

  testWidgets('설정: 말랑톡 서버에서 열면 서버 키 안내와 접속 코드 칸이 보이고, 내 키 없이 저장됨', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/settings');
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
        serverInfoProvider.overrideWith((ref) async => const ServerInfo(
              baseUrl: 'http://localhost:5200',
              providers: {AiProvider.claude},
              needsAccessCode: true,
            )),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
    expect(find.textContaining('Claude (Anthropic)는 서버 .env 키로'), findsOneWidget);
    expect(find.text('API 키 (안 넣어도 됨)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '서버 .env의 ACCESS_CODE'), 'mallang');
    await tester.tap(find.widgetWithText(OutlinedButton, '저장'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('server_access_code'), 'mallang');
    expect(prefs.getString('byok_provider'), 'claude'); // 키 없이도 저장됨
    expect(prefs.getString('byok_claude_model'), 'claude-opus-5-5');
  });

  testWidgets('만들기: 카이엔 설정을 불러오고, 쓰던 초안은 새로 열어도 남아 있음', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<void> openStudio() async {
      appRouter.go('/add');
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
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
    }

    await tester.binding.setSurfaceSize(const Size(420, 900));
    await openStudio();
    await tester.tap(find.byTooltip('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예시: 카이엔 (설정만)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('불러오기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '카이엔'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '카이엔'), '카이엔 루벨리아');
    await tester.pump(const Duration(seconds: 4)); // 자동 저장

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studio_draft_v1'), contains('카이엔 루벨리아'));

    // 앱을 새로 띄워도(새 버전·새로고침) 쓰던 초안이 그대로
    await openStudio();
    expect(find.widgetWithText(TextFormField, '카이엔 루벨리아'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '루벨리아 제국 제2황자'), findsOneWidget);
    appRouter.go('/friends'); // 만들기 화면을 닫아 자동 저장 타이머 정리
    await settle(tester);
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
    expect(find.text('1/9'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2/9'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '시각디자인과 4학년'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('3/9'), findsOneWidget);
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
