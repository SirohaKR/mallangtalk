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
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'fixtures/template_scenario.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 하단 탭(말랑이 찾기 / 채팅 / 내 말랑이 / 설정)이 있는 실제 앱 화면 흐름 테스트입니다.
void main() {
  ScenarioBundle loadIjun() => ScenarioBundle.fromJson(
        jsonDecode(File('test/fixtures/example_seo_ijun.json').readAsStringSync())
            as Map<String, dynamic>,
      );

  testWidgets('친구 탭: 맨 위 내 프로필, 별을 누르면 즐겨찾기로 올라감', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo, 'my_profile': '{"nickname":"쨋뀨","intro":"고양이 좋아함"}'});
    appRouter.go('/my');
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
    expect(find.text('캐릭터 삭제'), findsOneWidget);
    expect(find.text('고치기'), findsNothing);
    expect(find.text('캐릭터 파일'), findsNothing);
    // 프로필 사진을 누르면 크게, 누르면 다시 닫힘
    await tester.tap(find.byKey(const ValueKey('profile_photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo_viewer')), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo_viewer')), findsNothing);
    await tester.tap(find.text('1:1 채팅'));
    await tester.pumpAndSettle();
    expect(find.text('캐릭터 삭제'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    appRouter.go('/friends');
    await settle(tester);
  });

  testWidgets('채팅 탭에서 안 읽은 톡을 보고, 대화방에 들어가면 읽음 처리', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'chat_rooms_v1': [dohaId],
    });
    appRouter.go('/my');
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

    // 내 말랑이 탭, 기본 캐릭터 윤도하가 있음
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

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('말랑이 찾기')));
    await settle(tester);
    expect(find.text('오늘의 추천'), findsOneWidget);
    expect(find.text('새로 올라온 말랑이'), findsOneWidget);
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

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('말랑이 찾기')));
    await settle(tester);
    expect(find.text('말수 적은 사진 동아리 선배가 자꾸 출사에 부른다'), findsWidgets);
    await tester.ensureVisible(find.text('서이준').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('서이준').last);
    await settle(tester);

    // 상세: 소개 탭엔 캐릭터 정보·캐릭터 설정, 나머지는 세계관·나는 이 이야기에서·주변 인물 탭. 비밀과 제작용 정보는 안 보임
    for (final title in ['캐릭터 정보', '캐릭터 설정']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('시각디자인과 4학년'), findsOneWidget);
    expect(find.textContaining('몰래 저장해 둠'), findsNothing);
    await tester.tap(find.text('세계관'));
    await settle(tester);
    expect(find.text('세계관 설정'), findsOneWidget);
    expect(find.textContaining('대학 사진 동아리'), findsOneWidget);
    await tester.tap(find.text('나는 이 이야기에서'));
    await settle(tester);
    expect(find.text('말랑 · 사진 동아리에 새로 들어온 후배'), findsOneWidget);
    await tester.tap(find.text('주변 인물'));
    await settle(tester);
    expect(find.text('주변 인물'), findsNWidgets(2)); // 탭 이름 + 카드 제목
    expect(find.textContaining('몰래 저장해 둠'), findsNothing);
    // 대표 대사는 만들기 화면 안내대로 상세 화면 위쪽에 보임
    expect(find.textContaining('찍을 거 없으면 너라도 찍지 뭐.'), findsOneWidget);
    for (final hidden in ['관계 단계', '이야기 분량', '타자 스타일', '성격']) {
      expect(find.textContaining(hidden), findsNothing, reason: hidden);
    }

    // 아래 고정 버튼: 친구 추가하고 바로 대화 시작 창
    await tester.tap(find.text('친구 추가하고 대화하기'));
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(characterLibraryProvider).map((e) => e.id),
        contains('char_example_seo_ijun'));
    // 별명을 정하고 대화를 시작하기 전엔 톡이 오지 않음
    expect(container.read(chatRoomProvider('char_example_seo_ijun')).messages, isEmpty);
    expect(find.text('서이준과 어떻게 대화할까요?'), findsOneWidget);
    expect(find.widgetWithText(TextField, '말랑'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '후배님');
    await tester.ensureVisible(find.text('스토리 시작하기'));
    await tester.tap(find.text('스토리 시작하기'));
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
    expect(find.text('윤도하와 어떻게 대화할까요?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '말랑');
    // 별명과 함께 내 설정(페르소나)도 정하고, 다른 캐릭터에도 기본으로
    await tester.enterText(find.byKey(const ValueKey('persona_field')), '24살 대학원생, 밤에 러닝함');
    await tester.ensureVisible(find.text('다른 캐릭터에도 기본으로 쓰기'));
    await tester.tap(find.text('다른 캐릭터에도 기본으로 쓰기'));
    await tester.ensureVisible(find.text('스토리 시작하기'));
    await tester.tap(find.text('스토리 시작하기'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('persona_$dohaId'), '24살 대학원생, 밤에 러닝함');
    expect(prefs.getString('my_profile'), contains('밤에 러닝함'));

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

  testWidgets('설정 › AI 연결: 회사마다 키 칸만 있고, 키를 넣으면 그 회사로 쓸 수 있게 됨', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/settings/ai');
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
    // 모델 고르기는 없고 회사별 키 칸만
    expect(find.text('모델'), findsNothing);
    for (final p in AiProvider.values) {
      expect(find.byKey(ValueKey('ai_key_${p.name}')), findsOneWidget);
    }
    expect(find.text('무료로 키 받으러 가기 ›'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ai_key_claude')), 'sk-ant-new-key-123456');
    await tester.tap(find.byKey(const ValueKey('ai_keys_save')));
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('byok_key_claude') ?? prefs.getString('byok_claude_api_key'), 'sk-ant-new-key-123456');
    // 기본(Gemini)에 키가 없어서 키를 넣은 Claude가 모든 대화 기본이 됨
    expect(prefs.getString('byok_provider'), 'claude');
    expect(find.textContaining('저장된 키'), findsOneWidget);
    expect(find.textContaining('모든 대화 기본: Claude'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_key_remove_claude')));
    await settle(tester);
    expect(find.textContaining('저장된 키'), findsNothing);
  });

  testWidgets('설정: 말랑톡 서버에서 열면 서버 키 안내와 접속 코드 칸이 보이고, 내 키 없이 저장됨', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/settings/ai');
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
    expect(find.text('서버 키로 불러서 내 키는 안 넣어도 돼요'), findsOneWidget);

    // 접속 코드는 '고급' 안에 숨어 있음
    expect(find.widgetWithText(TextField, '서버 .env의 ACCESS_CODE'), findsNothing);
    await tester.tap(find.text('고급 · 서버 접속 코드'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '서버 .env의 ACCESS_CODE'), 'mallang');
    await tester.tap(find.widgetWithText(OutlinedButton, '저장'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('server_access_code'), 'mallang');
    // 서버 키가 있는 Claude가 내 키 없이 모든 대화 기본
    expect(find.textContaining('모든 대화 기본: Claude'), findsOneWidget);
  });

  testWidgets('만들기: 쓰던 초안은 새로 열어도 남아 있음', (tester) async {
    SharedPreferences.setMockInitialValues({'studio_draft_v1': jsonEncode(kaienScenario().toJson())});
    Future<void> openStudio() async {
      appRouter.go('/create');
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
    }

    await tester.binding.setSurfaceSize(const Size(420, 900));
    await openStudio();
    expect(find.text('새 말랑이 만들기'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '카이엔'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '카이엔'), '카이엔 루벨리아');
    await tester.pump(const Duration(seconds: 4)); // 자동 저장

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studio_draft_v1'), contains('카이엔 루벨리아'));

    // 앱을 새로 띄워도(새 버전·새로고침) 쓰던 초안이 그대로
    await openStudio();
    expect(find.widgetWithText(TextFormField, '카이엔 루벨리아'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio_step_2'))); // 위 막대로 3단계 프로필로 바로
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '루벨리아 제국 제2황자'), findsOneWidget);
    appRouter.go('/friends'); // 만들기 화면을 닫아 자동 저장 타이머 정리
    await settle(tester);
  });

  testWidgets('만들기: 쓰던 초안을 대사 탭에서 고치고 저장하면 내 캐릭터에 생김', (tester) async {
    SharedPreferences.setMockInitialValues({'studio_draft_v1': jsonEncode(templateScenario().toJson())});
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
    expect(find.text('1 / 8'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '서이준'), findsOneWidget);

    // 한 화면에 한 단계씩 '다음'으로 넘김: 기본 → 대표색 → 프로필 … 이야기(넓은 칸 + 글자 수)
    await tester.tap(find.byKey(const ValueKey('studio_next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.byKey(const ValueKey('studio_color_preview')), findsOneWidget);
    // 무지개 버튼 → 끌어서 색 고르기 → 직접 고르기 칸에 들어감
    await tester.tap(find.byKey(const ValueKey('studio_color_rainbow')));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('color_picker_hue')), const Offset(80, 0));
    await tester.drag(find.byKey(const ValueKey('color_picker_area')), const Offset(-40, 30));
    await tester.pump();
    final picked = tester.widget<Text>(find.byKey(const ValueKey('color_picker_hex'))).data!;
    expect(RegExp(r'^#[0-9A-F]{6}$').hasMatch(picked), isTrue);
    await tester.tap(find.byKey(const ValueKey('color_picker_done')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, picked), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio_next')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 8'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '시각디자인과 4학년'), findsOneWidget);
    await tester.tap(find.text('여성'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio_step_4')));
    await tester.pumpAndSettle();
    expect(find.text('5 / 8'), findsOneWidget);
    final setting = templateScenario().character.worldviewPrompt;
    expect(find.text('${setting.characters.length}자'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, setting), '$setting 커피는 늘 블랙.');
    await tester.pump();
    expect(find.text('${setting.characters.length + 10}자'), findsOneWidget);

    // 7단계 호감도·대본: 첫 대화를 펼쳐 대사 편집으로 들어가 첫 말풍선을 고침
    await tester.tap(find.byKey(const ValueKey('studio_step_6')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('studio_ai_generate')), findsOneWidget);
    await tester.tap(find.text('1. ${templateScenario().events.first.title}'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('대사 편집').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('대사 편집').first);
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
    expect(made.bundle.character.gender, 'female');
    // 저장하면 새 캐릭터를 만들 수 있게 빈 칸으로 돌아감
    expect(find.widgetWithText(TextFormField, '서이준'), findsNothing);
  });

  testWidgets('만들기: 사진을 안 고른 사진 말풍선이 있으면 저장 전에 알려 주고, 수정하러 가기로 그 자리로 감', (tester) async {
    // 1x1 PNG
    const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
    final draft = ScenarioDraft.fromBundle(templateScenario());
    final event = draft.events.first;
    draft.addPhoto(png);
    // 사진함엔 사진 1장, 빈 자리 2곳(설명이 서로 다름) → 자동으로 못 붙임
    event.scenes.last.lines.addAll([LineDraft(photo: '필름 카메라 셀카'), LineDraft(photo: '노을 진 옥상')]);
    event.cutscene = '';
    SharedPreferences.setMockInitialValues({'studio_draft_v1': jsonEncode(draft.toBundle().toJson())});
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

    // 7단계 대화 카드에 사진 꼬리표
    await tester.tap(find.byKey(const ValueKey('studio_step_6')));
    await tester.pumpAndSettle();
    expect(find.text('사진 말풍선 0/2'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('사진을 안 고른 곳이 있어요'), findsOneWidget);
    expect(find.textContaining('"필름 카메라 셀카"'), findsOneWidget);
    // 사진함에 안 쓴 사진이 있으면 다른 대화의 빈 컷씬도 알려 줌
    expect(find.text('수정하러 가기'), findsNWidgets(4));

    await tester.tap(find.text('수정하러 가기').at(1));
    await tester.pumpAndSettle();
    expect(find.text('사진을 안 고른 곳이 있어요'), findsNothing);
    // 대사 탭에서 그 대화가 열리고, 고를 말풍선이 화면에 보임
    expect(find.text('이 대화의 사진'), findsOneWidget);
    expect(find.text('사진함 열기'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '노을 진 옥상'), findsOneWidget);
    expect(find.text('사진 말풍선 · 사진함에 사진이 있는데 아직 안 골랐어요'), findsNWidgets(2));
    final target = tester.getRect(find.widgetWithText(TextFormField, '노을 진 옥상'));
    expect(target.top, greaterThanOrEqualTo(0));
    expect(target.bottom, lessThanOrEqualTo(900));

    // 그냥 저장도 됨
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그냥 저장'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(characterLibraryProvider), hasLength(2));
  });
}
