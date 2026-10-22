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

    // 상세: 대표 대사·프로필·유저 설정이 보이고, 비밀은 개수만
    expect(find.text('“찍을 거 없으면 너라도 찍지 뭐.”'), findsOneWidget);
    expect(find.text('시각디자인과 4학년'), findsOneWidget);
    expect(find.text('말랑 · 사진 동아리에 새로 들어온 후배'), findsOneWidget);
    expect(find.textContaining('몰래 저장해 둠'), findsNothing);
    expect(find.text('아직 모르는 비밀 2개'), findsOneWidget);

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
}
