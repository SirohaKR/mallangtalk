import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 대화방 메뉴 › 기억 노트: 쌓인 한 줄 기억을 보고 고치고 지우고 더하면 바로 저장됨
void main() {
  testWidgets('기억 노트에서 기억을 고치고 지우고 더함', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(const SavedRun(
        affection: 0, flags: [], completedEventIds: [], messages: [],
        memories: ['주말에 산책하기로 했다', '시험을 망쳐서 위로해 줬다'],
      ).toJson()),
    });
    final container = await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.byTooltip('대화 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기억 노트 (2)'));
    await tester.pumpAndSettle();
    expect(find.text('주말에 산책하기로 했다'), findsOneWidget);

    // 지우기 (최근 기억이 위라 두 번째 줄이 '주말에…')
    await tester.tap(find.byTooltip('지우기').last);
    await tester.pumpAndSettle();
    expect(find.text('주말에 산책하기로 했다'), findsNothing);

    // 고치기
    await tester.tap(find.byTooltip('고치기').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('memory_edit_field')), '시험 끝나고 같이 떡볶이 먹기로 했다');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 더하기
    await tester.tap(find.byKey(const ValueKey('memory_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('memory_edit_field')), '  내가 고양이 알레르기가 있다고 했다 ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    const want = ['시험 끝나고 같이 떡볶이 먹기로 했다', '내가 고양이 알레르기가 있다고 했다'];
    expect(container.read(chatRoomProvider(room)).memories, want);
    expect(container.read(localStoreProvider).loadRun(room)!.memories, want);
    await settle(tester);
  });
}
