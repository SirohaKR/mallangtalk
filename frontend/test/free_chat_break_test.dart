import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('10분 쉬고 보낸 첫 톡 앞에만 구분선을 저장하고 기존 기록과 기억을 유지함', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(const SavedRun(
        affection: 0, flags: [], completedEventIds: [], messages: [],
        memories: ['유저와 주말에 산책하기로 했다'],
      ).toJson()),
    });
    var now = testNow();
    final container = await openDohaChat(tester, roomId: room, extra: [
      ...testAiOverrides,
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = container.read(chatRoomProvider(room).notifier);
    ChatRoomState state() => container.read(chatRoomProvider(room));
    notifier.sendUserMessage(text: '산책 중이야');
    await settle(tester);
    now = now.add(const Duration(minutes: 9));
    notifier.sendUserMessage(text: '아직 걷고 있어');
    await settle(tester);
    expect(state().messages.where((m) => m.isConversationBreak), isEmpty);
    final memories = [...state().memories];
    final previousIds = state().messages.map((m) => m.id).toList();

    now = now.add(const Duration(minutes: 10));
    notifier.sendUserMessage(text: '아까 말했던 곳 기억나?');
    notifier.sendUserMessage(text: '거기 다시 가자');
    await tester.pump();
    expect(state().messages.where((m) => m.isConversationBreak), hasLength(1));
    expect(state().messages.map((m) => m.id), containsAllInOrder(previousIds));
    expect(state().memories, memories);
    final saved = container.read(localStoreProvider).loadRun(room)!;
    expect(saved.messages.where((m) => m.isConversationBreak), hasLength(1));
    expect(saved.memories, memories);
    expect(find.textContaining('새로운 대화 ·'), findsOneWidget);
    await settle(tester);

    // 새로고침 뒤에도 같은 경계가 남고, 바로 이어 쓰면 중복하지 않는다.
    final reopened = await openDohaChat(tester, roomId: room, extra: [
      ...testAiOverrides,
      clockProvider.overrideWithValue(() => now),
    ]);
    reopened.read(chatRoomProvider(room).notifier).sendUserMessage(text: '다시 왔어');
    expect(reopened.read(chatRoomProvider(room)).messages.where((m) => m.isConversationBreak), hasLength(1));
    await settle(tester);
  });
}
