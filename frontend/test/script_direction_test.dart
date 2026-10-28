import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 첫 장면을 바꾼 윤도하: 내가 먼저 선톡을 보내고, 캐릭터 첫 답장은 늦게 옴
ScenarioBundle _userFirstLateBundle() {
  final base = loadSampleBundle();
  final first = base.firstNodeOf(base.events.first.id)!;
  final changed = ScriptNodeModel(
    id: first.id,
    eventId: first.eventId,
    stepOrder: first.stepOrder,
    speakerCharacterId: first.speakerCharacterId,
    userFirst: const [ScriptBubblePiece(text: '도하야 자?'), ScriptBubblePiece(text: '두부는?')],
    characterBubbles: [
      ScriptBubblePiece(text: '아 미안 씻고 왔어', delaySeconds: first.characterBubbles.first.delaySeconds + 10),
      ...first.characterBubbles.skip(1),
    ],
    choices: first.choices,
  );
  return ScenarioBundle(
    character: base.character,
    events: base.events,
    nodes: {...base.nodes, first.id: changed},
    images: base.images,
  );
}

void main() {
  test('선톡과 늦은 답장은 파일로 저장했다 불러와도 남음', () {
    final node = _userFirstLateBundle().firstNodeOf('evt_dubu_missing')!;
    final again = ScriptNodeModel.fromJson(node.toJson());
    expect(again.userFirst.map((b) => b.text), ['도하야 자?', '두부는?']);
    expect(again.characterBubbles.first.delaySeconds, 10);

    // 만들기 화면에서 열었다 저장해도 그대로
    final saved = ScenarioDraft.fromBundle(_userFirstLateBundle()).toBundle();
    final first = saved.firstNodeOf(saved.events.first.id)!;
    expect(first.userFirst.map((b) => b.text), ['도하야 자?', '두부는?']);
    expect(first.characterBubbles.first.delaySeconds, 10);
  });

  testWidgets('선톡: 내가 먼저 보내고, 늦은 답장이 올 때까지 1이 남음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester, bundle: _userFirstLateBundle());
    // openDohaChat은 다 끝날 때까지 기다리므로 결과만 확인
    final state = container.read(chatRoomProvider(dohaId));
    final texts = state.messages.where((m) => !m.isSystem).map((m) => m.text).toList();
    expect(texts.take(3), ['도하야 자?', '두부는?', '아 미안 씻고 왔어']);
    expect(state.messages.where((m) => m.isUser).first.isUnread, isFalse); // 답장이 오면 읽음
  });

  testWidgets('늦은 답장 전에는 내 톡에 1이 남아 있음', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final bundle = _userFirstLateBundle();
    await openDohaChat(tester, bundle: bundle);
    // 처음부터 다시 하면서 중간을 들여다봄
    final container = await openDohaChat(tester, bundle: bundle);
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.restart();
    var sawUnreadWhileWaiting = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final s = container.read(chatRoomProvider(dohaId));
      final users = s.messages.where((m) => m.isUser).toList();
      if (users.length == 2 && users.every((m) => m.isUnread) && s.messages.where((m) => !m.isUser && !m.isSystem).isEmpty) {
        sawUnreadWhileWaiting = true;
      }
    }
    expect(sawUnreadWhileWaiting, isTrue);
    await settle(tester);
  });
}
