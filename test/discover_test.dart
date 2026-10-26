import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/discover/discover_screen.dart';
import 'package:mallangtalk/features/discover/gallery_card.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 말랑이 찾기: 오늘의 추천·정렬·검색·제작자
void main() {
  GalleryItem item(String id, String name,
          {String creator = '쨋뀨',
          int friends = 0,
          int daysAgo = 0,
          List<String> tags = const [],
          String tagline = '',
          String gender = ''}) =>
      GalleryItem(
        ScenarioBundle(
          character:
              loadSampleBundle().character.copyWith(id: id, name: name, tags: tags, tagline: tagline, gender: gender),
          events: const [],
          nodes: const {},
        ),
        creator: creator,
        friends: friends,
        createdAt: DateTime(2026, 10, 26).subtract(Duration(days: daysAgo)),
      );

  test('오늘의 추천은 친구 수가 많은 말랑이 위주, 막 올라온 말랑이도 끼워 줌', () {
    final items = [
      item('a', '오래된 인기', friends: 20, daysAgo: 60),
      item('b', '어제 올라옴', friends: 0, daysAgo: 0),
      item('c', '조용한 옛날', friends: 0, daysAgo: 90),
    ];
    final picks = recommendedOf(items, now: DateTime(2026, 10, 26), count: 2).map((g) => g.character.id);
    expect(picks, ['a', 'b']);
  });

  test('많이 쓴 태그 순서, 검색은 이름·태그·만든 사람·한줄 소개', () {
    final items = [
      item('a', '카이엔', tags: ['로판', '황자'], tagline: '모범생 황자님'),
      item('b', '서이준', tags: ['로판', '대학'], creator: '말랑작가'),
    ];
    expect(topTagsOf(items).first, '로판');
    expect(items.where((g) => g.matches('#황자')).map((g) => g.character.id), ['a']);
    expect(items.where((g) => g.matches('말랑작가')).map((g) => g.character.id), ['b']);
    expect(items.where((g) => g.matches('모범생')).map((g) => g.character.id), ['a']);
    expect(items.where((g) => g.matches('')).length, 2);
  });

  test('성별 필터: 남성·여성만 골라 보고, 성별을 안 고른 말랑이는 미정에 함께', () {
    final items = [
      item('a', '카이엔', gender: 'male'),
      item('b', '서윤', gender: 'female'),
      item('c', '말랑', gender: 'none'),
      item('d', '안 고름'),
    ];
    ids(String? g) => genderFiltered(items, g).map((e) => e.character.id).toList();
    expect(ids(null), ['a', 'b', 'c', 'd']);
    expect(ids('male'), ['a']);
    expect(ids('female'), ['b']);
    expect(ids('none'), ['c', 'd']);
  });

  testWidgets('제작자 동그라미는 그 사람 프로필 사진을 쓰고, 사진이 없으면 이름 첫 글자', (tester) async {
    // 1×1 투명 png
    const photo = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4z'
        'wAAAgEBAFzN8/8AAAAASUVORK5CYII=';
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        CreatorAvatar(name: '쨋뀨', avatarUrl: photo, size: 40),
        CreatorAvatar(name: '말랑작가', size: 40),
      ]),
    ));
    await tester.pump();
    expect(find.text('쨋'), findsNothing); // 사진이 있으면 첫 글자 대신 사진
    expect(find.text('말'), findsOneWidget);
    final withPhoto = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).single;
    expect(withPhoto.backgroundImage, isA<MemoryImage>());
  });

  testWidgets('제작자 프로필에 사진과 한줄 소개가 보임', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/creator/${Uri.encodeComponent('말랑작가')}');
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final mine = GalleryItem(
      ScenarioBundle(
        character: loadSampleBundle().character.copyWith(id: 'z', name: '카이엔'),
        events: const [],
        nodes: const {},
      ),
      creator: '말랑작가',
      creatorIntro: '로판 말랑이만 만들어요',
      createdAt: DateTime(2026, 10, 26),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => []),
        galleryProvider.overrideWith((ref) async => [mine]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('말랑작가'), findsOneWidget);
    expect(find.text('로판 말랑이만 만들어요'), findsOneWidget);
  });

  testWidgets('첫 화면은 말랑이 찾기, 검색창을 누르면 검색 화면에서 바로 찾음', (tester) async {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/discover');
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
      ],
      child: const MallangTalkApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 추천'), findsOneWidget);
    expect(find.text('윤도하'), findsWidgets);
    // 샘플 윤도하는 성별을 안 골라서 미정: 남성을 고르면 비고, 다시 누르면 전체
    await tester.tap(find.byKey(const ValueKey('gender_male')));
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 말랑이가 없어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gender_male')));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 추천'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discover_search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '없는이름');
    await tester.pump();
    expect(find.text("'없는이름'에 맞는 말랑이가 없어요"), findsOneWidget);
    await tester.enterText(find.byType(TextField), '도하');
    await tester.pump();
    expect(find.text('윤도하'), findsOneWidget);
    await tester.tap(find.text('윤도하'));
    await tester.pumpAndSettle();
    expect(find.text('대화하러 가기'), findsOneWidget); // 처음부터 친구라 바로 대화
  });

  testWidgets('내 말랑이: 오른쪽 위 만들기 버튼으로 새 말랑이 만들기 화면', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('내가 만든'));
    await tester.pumpAndSettle();
    expect(find.text('새 말랑이 만들기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my_create')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 8'), findsOneWidget);
    appRouter.go('/my'); // 만들기 화면을 닫아 자동 저장 타이머 정리
    await tester.pumpAndSettle();
  });
}
