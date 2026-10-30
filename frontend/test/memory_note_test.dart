import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 대화방 사이드바 › 로어북: 쌓인 한 줄 기억을 보고 고치고 지우고 더하면 바로 저장됨
void main() {
  testWidgets('로어북에서 기억을 고치고 지우고 더함 ([제목][세부사항])', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(const SavedRun(
        affection: 0, flags: [], completedEventIds: [], messages: [],
        memories: ['주말에 산책하기로 했다', '시험\n시험을 망쳐서 위로해 줬다'],
      ).toJson()),
    });
    final container = await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('쌓인 기억 2개 · 보고 고치기'), findsOneWidget);
    await tester.tap(find.text('로어북'));
    await tester.pumpAndSettle();
    expect(find.text('주말에 산책하기로 했다'), findsOneWidget);
    expect(find.text('시험'), findsOneWidget); // 제목

    // 지우기 (최근 기억이 위라 두 번째 줄이 '주말에…')
    await tester.tap(find.byTooltip('지우기').last);
    await tester.pumpAndSettle();
    expect(find.text('주말에 산책하기로 했다'), findsNothing);

    // 고치기
    await tester.tap(find.byTooltip('고치기').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('memory_title_field')), '떡볶이 약속');
    await tester.enterText(find.byKey(const ValueKey('memory_edit_field')), '시험 끝나고 같이 떡볶이 먹기로 했다');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 더하기
    await tester.tap(find.byKey(const ValueKey('memory_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('memory_title_field')), ' 고양이 알레르기 ');
    await tester.enterText(find.byKey(const ValueKey('memory_edit_field')), '  내가 고양이 알레르기가 있다고 했다 ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    const want = ['떡볶이 약속\n시험 끝나고 같이 떡볶이 먹기로 했다', '고양이 알레르기\n내가 고양이 알레르기가 있다고 했다'];
    expect(container.read(chatRoomProvider(room)).memories, want);
    expect(container.read(localStoreProvider).loadRun(room)!.memories, want);
    await settle(tester);
  });

  testWidgets('/구분선은 구분선을 넣고, /비우기는 묻고 나서 비움', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(SavedRun(
        affection: 0, flags: const [], completedEventIds: const [],
        messages: [ChatMessageLog(id: 'a', isUser: true, speakerCharacterId: 'user', speakerName: '나', text: '안녕', timestamp: DateTime(2026))],
        memories: const ['남은 기억'],
      ).toJson()),
    });
    final container = await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChatRoomState state() => container.read(chatRoomProvider(room));

    // '/'만 쳐도 명령어 목록이 뜸
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    expect(find.byKey(const ValueKey('command_구분선')), findsOneWidget);
    expect(find.byKey(const ValueKey('command_비우기')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '/구분선');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(state().messages.where((m) => m.isConversationBreak), hasLength(1));
    expect(state().messages.where((m) => m.text == '/구분선'), isEmpty);

    await tester.enterText(find.byType(TextField), '/비우기');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(state().messages, isEmpty);
    expect(state().memories, ['남은 기억']);
    await settle(tester);
  });
}
