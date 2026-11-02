import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/scene/scene_room.dart';
import 'package:mallangtalk/features/scene/scene_screen.dart';
import 'package:mallangtalk/features/settings/byok_settings.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 내 톡(현실 장면 방은 내 입력)마다 쓰레기통·재전송
void main() {
  ChatMessageLog msg(String id, bool user, String text) => ChatMessageLog(
      id: id,
      isUser: user,
      speakerCharacterId: user ? 'user' : dohaId,
      speakerName: user ? '쨋뀨' : '윤도하',
      text: text,
      timestamp: DateTime(2026, 10, 22, 14));

  testWidgets('자유대화 방: 재전송은 마지막 내 톡만, 예상 사용량을 보여 주고 답장만 다시 받음 / 쓰레기통은 내 톡+답장을 지움', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(SavedRun(
        affection: 0,
        flags: const [],
        completedEventIds: const [],
        messages: [
          msg('a', true, '첫 톡'),
          msg('b', false, '첫 답'),
          msg('b2', false, '첫 답 둘'),
          msg('c1', true, '나중 톡'),
          msg('c2', true, '나중 톡 둘'),
          msg('d', false, '옛 답장'),
        ],
      ).toJson()),
    });
    final fake = _ReplyFake();
    final container = await openDohaChat(tester, roomId: room, extra: [
      byokSettingsProvider.overrideWith(_Ai.new),
      claudeChatClientProvider.overrideWithValue(fake),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 연달아 보낸 내 톡 묶음의 마지막 아래에만 버튼, 재전송은 맨 마지막 묶음만
    expect(find.byKey(const ValueKey('turn_delete_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('turn_resend_a')), findsNothing);
    expect(find.byKey(const ValueKey('turn_delete_c1')), findsNothing);
    expect(find.byKey(const ValueKey('turn_delete_c2')), findsOneWidget);
    expect(find.byKey(const ValueKey('turn_resend_c2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('turn_resend_c2')));
    await tester.pumpAndSettle();
    final cost = tester.widget<Text>(find.byKey(const ValueKey('resend_cost'))).data!;
    expect(cost, contains('예상 사용량: 약'));
    expect(cost, contains('토큰'));
    await tester.tap(find.text('다시 받기'));
    await settle(tester);

    expect(fake.newUserMessages.single, ['나중 톡', '나중 톡 둘']);
    expect(fake.histories.single.map((m) => m.text), isNot(contains('옛 답장')));
    var texts = container.read(chatRoomProvider(room)).messages.map((m) => m.text).toList();
    expect(texts, ['첫 톡', '첫 답', '첫 답 둘', '나중 톡', '나중 톡 둘', '새 답장']);

    // 쓰레기통: 첫 톡과 그 답장 둘이 같이 지워짐 (확인 창에서 '지우기')
    await tester.tap(find.byKey(const ValueKey('turn_delete_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    texts = container.read(chatRoomProvider(room)).messages.map((m) => m.text).toList();
    expect(texts, ['나중 톡', '나중 톡 둘', '새 답장']);
    final saved = container.read(localStoreProvider).loadRun(room)!;
    expect(saved.messages, hasLength(3));
    // 지운 시각을 남겨서 다른 기기에 남은 지우기 전(더 긴) 대화가 연동 때 이기지 않게
    expect(saved.resetAt, isNotNull);
  });

  testWidgets('현실 장면 방: 내 입력마다 쓰레기통, 마지막 입력은 재전송으로 장면만 다시 받음', (tester) async {
    final room = freeRoomId(dohaId);
    final now = DateTime(2026).toIso8601String();
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'scene_$room': jsonEncode({'lines': [
        {'kind': 'start', 'id': 's', 'text': '톡', 'context': 'c', 'at': now},
        {'kind': 'story', 'id': 'st0', 'text': '(첫 장면)', 'at': now},
        {'kind': 'user', 'id': 'u1', 'text': '입력 하나', 'at': now},
        {'kind': 'story', 'id': 'st1', 'text': '(장면 하나)', 'at': now},
        {'kind': 'user', 'id': 'u2', 'text': '입력 둘', 'at': now},
        {'kind': 'story', 'id': 'st2', 'text': '(옛 장면 둘)', 'at': now},
      ]}),
    });
    final fake = _ReplyFake();
    final container = await openDohaChat(tester, roomId: room, extra: [
      byokSettingsProvider.overrideWith(_Ai.new),
      claudeChatClientProvider.overrideWithValue(fake),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Navigator.of(tester.element(find.byType(Scaffold).first))
        .push(MaterialPageRoute<void>(builder: (_) => SceneScreen(sourceRoomId: room)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scene_delete_u1')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene_resend_u1')), findsNothing);
    expect(find.byKey(const ValueKey('scene_resend_u2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scene_resend_u2')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('scene_resend_cost'))).data, contains('예상 사용량'));
    await tester.tap(find.text('다시 받기'));
    await tester.pumpAndSettle();
    expect(fake.sceneInputs.single, '입력 둘');
    final lines = () => container.read(sceneRoomProvider(room)).lines.map((l) => l.text).toList();
    expect(lines(), ['톡', '(첫 장면)', '입력 하나', '(장면 하나)', '입력 둘', '(새 장면)']);

    await tester.tap(find.byKey(const ValueKey('scene_delete_u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(lines(), ['톡', '(첫 장면)', '입력 둘', '(새 장면)']);

    // 메뉴는 톡 방처럼 오른쪽 사이드바
    await tester.tap(find.byKey(const ValueKey('scene_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene_side_lorebook')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene_side_ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene_side_end')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene_side_clear')), findsOneWidget);
  });
}

class _Ai extends ByokSettingsNotifier {
  @override
  ByokSettings build() => const ByokSettings(apiKey: 'test-key', model: 'claude-sonnet-5-5');
}

class _ReplyFake extends ClaudeChatClient {
  _ReplyFake() : super(dio: Dio());
  final newUserMessages = <List<String>>[];
  final histories = <List<ChatMessageLog>>[];
  final sceneInputs = <String?>[];

  @override
  Future<FreeChatReply> reply({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String? stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
    String userName = '너',
    String userIntro = '',
    String userPersona = '',
    FreeTalkPace pace = FreeTalkPace.open,
    List<String> memories = const [],
    List<FreeTalkPhoto> photos = const [],
    void Function(Duration wait)? onRetryWait,
  }) async {
    this.newUserMessages.add(newUserMessages);
    histories.add(history);
    return const FreeChatReply(bubbles: ['새 답장'], affectionDelta: 0);
  }

  @override
  Future<String> sceneTurn({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String userName,
    String userIntro = '',
    String userPersona = '',
    List<String> memories = const [],
    required String talkContext,
    required List<({bool isUser, String text})> scene,
    String? userInput,
    void Function(Duration wait)? onRetryWait,
  }) async {
    sceneInputs.add(userInput);
    return '(새 장면)';
  }
}
