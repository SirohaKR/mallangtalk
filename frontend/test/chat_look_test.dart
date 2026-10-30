import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/theme/app_colors.dart';
import 'package:mallangtalk/features/chat/affection_gauge.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_theme.dart';
import 'package:mallangtalk/features/settings/byok_settings.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 톡방 대표색 꾸미기, 앨범(사진 전부), 사진 크게 보기, 호감도 말랑이
void main() {
  const dubuPhoto = '빨래 더미 속에서 눈만 내놓고 있는 회색 고양이 두부 사진';
  const dubuCutscene = '빨래 바구니에서 꺼낸 두부를 안고 안도의 한숨을 쉬는 도하';

  test('대표색으로 톡방 색이 정해지고, 비어 있으면 예전 분홍', () {
    final doha = loadSampleBundle().character; // 대표색 #6B8FD6
    final theme = ChatTheme.of(doha);
    expect(theme.myBubble, const Color(0xFF6B8FD6));
    expect(theme.myText, AppColors.surfaceWhite, reason: '진한 말풍선엔 흰 글자');
    expect(theme.background, isNot(AppColors.surfaceWhite));

    expect(ChatTheme.of(doha.copyWith(themeColor: '')).myBubble, AppColors.myBubble);
    final pinkBubble = ChatTheme.of(doha.copyWith(bubbleStyle: 'pink', chatBackground: 'white'));
    expect(pinkBubble.myBubble, AppColors.myBubble);
    expect(pinkBubble.myText, AppColors.textPrimary, reason: '밝은 말풍선엔 검은 글자');
    expect(pinkBubble.background, AppColors.surfaceWhite);

    // 사진 배경: 사진이 있을 때만, 파일로 저장했다 불러와도 그대로
    const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
    final photo = doha.copyWith(chatBackground: 'photo', chatBackgroundImage: png);
    expect(ChatTheme.of(photo).backgroundImage, png);
    expect(ChatTheme.of(photo.copyWith(themeColor: '')).backgroundImage, png);
    expect(ChatTheme.of(doha.copyWith(chatBackground: 'photo')).backgroundImage, isNull);
    expect(ChatTheme.of(CharacterModel.fromJson(photo.toJson())).backgroundImage, png);
  });

  test('앨범에는 사진 말풍선과 컷씬이 구분 없이, 같은 설명은 한 번만, 호감도 단계로 묶여 들어감', () {
    final bundle = loadSampleBundle();
    final photos = bundle.albumPhotos;
    final labels = photos.map((p) => p.label).toList();
    expect(labels, containsAll([dubuPhoto, dubuCutscene]));
    expect(labels.toSet().length, labels.length);
    // 사진 말풍선 9장 + 컷씬 4장
    expect(photos, hasLength(13));
    expect(photos.first.group, '편한 친구', reason: '단계 이름이 없는 이벤트는 열리는 호감도로 단계를 찾음');
  });

  test('호감도 말랑이는 단계 수에 맞춰 차오름', () {
    final doha = loadSampleBundle().character;
    expect(AffectionGauge.fillOf(doha, doha.affectionStages.first.minScore), 0);
    final last = doha.affectionStages.last;
    expect(AffectionGauge.fillOf(doha, last.maxScore), closeTo(1, 0.01));
    final mid = AffectionGauge.fillOf(doha, doha.affectionStages[1].minScore);
    expect(mid, closeTo(1 / 3, 0.01));
  });

  testWidgets('받은 사진은 앨범에 쌓이고, 대화방 사진을 누르면 크게 보기가 열림', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester);
    ChatRoomState state() => container.read(chatRoomProvider(dohaId));

    await choose(tester, '지금 바로 같이 찾으러 가겠다고 하기');
    expect(state().receivedPhotos, containsAll([dubuPhoto, dubuCutscene]));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('photos_$dohaId'), contains(dubuPhoto));

    await tester.tap(find.text('탭하여 사진 크게 보기').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('photo_viewer')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('photo_viewer')), matching: find.text(dubuPhoto)),
        findsWidgets);
    // 진짜 사진이 없는 설명 카드라 '저장'은 없고, '이 톡으로 가기'는 닫고 그 톡으로
    expect(find.byKey(const ValueKey('photo_viewer_save')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('photo_viewer_goto')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('photo_viewer')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('예전 앨범(컷씬만 기록)도 새 앨범에 들어감', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'album_$dohaId': ['evt_dubu_missing'],
    });
    final container = await openDohaChat(tester);
    expect(container.read(chatRoomProvider(dohaId)).receivedPhotos, contains(dubuCutscene));
  });

  testWidgets('대화방 메뉴에서 자유대화 AI를 고르면 모델이 바로 바뀌고, 키 없는 회사는 그 자리에서 키를 넣음', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_provider': 'gemini',
      'byok_key_gemini': 'AIza-test',
      'byok_model_gemini': 'gemini-3.8-flash',
    });
    final container = await openDohaChat(tester);
    await tester.tap(find.byTooltip('메뉴'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('대화 설정'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('AI 모델'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('자유대화 AI'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_model_gemini-3.5-flash-lite')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(byokSettingsProvider).model, 'gemini-3.5-flash-lite');

    // 키가 없는 Claude를 누르면 키 넣는 칸이 나오고, 넣으면 바로 Claude로 바뀜
    await tester.tap(find.byKey(const ValueKey('ai_provider_claude')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('chat_ai_key')), 'sk-ant-test');
    await tester.pump();
    await tester.tap(find.text('연결하고 쓰기'));
    await tester.pump(const Duration(milliseconds: 300));
    final byok = container.read(byokSettingsProvider);
    expect(byok.provider.name, 'claude');
    expect(byok.hasKey, isTrue);
  });

  testWidgets('대화방 AI를 이 대화만으로 고르면 그 방만 바뀌고 다른 대화는 기본 AI 그대로', (tester) async {
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'byok_provider': 'gemini',
      'byok_key_gemini': 'AIza-test',
      'byok_model_gemini': 'gemini-3.8-flash',
      'byok_claude_api_key': 'sk-ant-test',
    });
    final container = await openDohaChat(tester);
    await tester.tap(find.byTooltip('메뉴'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('대화 설정'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('AI 모델'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 스토리 방에서 열면 자유대화 스위치는 꺼져 있음 (켜면 자유대화 방으로)
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('ai_free_switch'))).value, isFalse);
    await tester.tap(find.text('이 대화만'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ai_provider_claude')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ai_model_claude-haiku-5-5')));
    await tester.pump(const Duration(milliseconds: 300));

    final here = container.read(roomByokProvider(dohaId));
    expect(here.provider.name, 'claude');
    expect(here.model, 'claude-haiku-5-5');
    // 모든 대화 기본(다른 방)은 그대로 Gemini
    expect(container.read(byokSettingsProvider).provider.name, 'gemini');
    expect(container.read(roomByokProvider('other_room')).model, 'gemini-3.8-flash');

    // 모든 대화 기본으로 바꾸면 지금 고른 AI가 기본이 되고, 이 방의 따로 설정은 지워짐
    await tester.tap(find.text('모든 대화 기본으로'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(roomAiChoiceProvider(dohaId)), isNull);
    expect(container.read(byokSettingsProvider).provider.name, 'claude');
    expect(container.read(byokSettingsProvider).model, 'claude-haiku-5-5');
  });
}
