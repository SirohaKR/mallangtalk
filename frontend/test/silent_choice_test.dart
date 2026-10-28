import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'test_helpers.dart';

void main() {
  test('진행 선택지의 빈 실제 대사를 버튼 문구로 대체하지 않음', () {
    final draft = ScenarioDraft.fromBundle(loadSampleBundle());
    final choice = draft.events.first.scenes.first.choices.first;
    choice.label = '이어서 듣기';
    choice.messages = '';
    final bundle = draft.toBundle();
    final saved = bundle.firstNodeOf(bundle.events.first.id)!.choices.first;
    expect(saved.buttonLabel, '이어서 듣기');
    expect(saved.userBubbles, isEmpty);
  });
  testWidgets('기존 데이터의 이어서 듣기도 실제 대사 없이 다음 분기로 진행', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = container.read(chatRoomProvider(dohaId));
    final choice = before.currentChoices.first;
    container.read(chatRoomProvider(dohaId).notifier).selectChoice(ChoiceOption(
        id: 'listen',
        buttonLabel: '이어서 듣기',
        userBubbles: const [ScriptBubblePiece(text: '이어서 듣기')],
        affectionDelta: choice.affectionDelta,
        nextNodeId: choice.nextNodeId));
    await settle(tester);
    final after = container.read(chatRoomProvider(dohaId));
    expect(after.messages.where((m) => m.isUser), isEmpty);
    expect(after.messages.length, greaterThan(before.messages.length));
  });
  testWidgets('침묵 선택지는 타자와 말풍선 없이 다음 분기로 진행', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final container = await openDohaChat(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = container.read(chatRoomProvider(dohaId));
    final choice = before.currentChoices.first;
    final notifier = container.read(chatRoomProvider(dohaId).notifier);
    notifier.selectChoice(ChoiceOption(
        id: 'silent',
        buttonLabel: '답장하지 않는다',
        userBubbles: const [ScriptBubblePiece(text: '(답장하지 않는다)')],
        affectionDelta: choice.affectionDelta,
        nextNodeId: choice.nextNodeId));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(chatRoomProvider(dohaId)).userDraft, isEmpty);
    await settle(tester);
    final after = container.read(chatRoomProvider(dohaId));
    expect(after.messages.where((m) => m.isUser), isEmpty);
    expect(after.messages.length, greaterThan(before.messages.length));
    expect(find.text('(답장하지 않는다)'), findsNothing);
  });
  testWidgets('자유대화 침묵은 AI 문맥에 보존하고 화면과 미리보기에는 숨김', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container
        .read(chatRoomProvider(room).notifier)
        .sendUserMessage(text: '(답장하지 않는다)');
    await tester.pump();
    var state = container.read(chatRoomProvider(room));
    expect(state.messages.single.isHidden, isTrue);
    expect(state.lastBubble, isNull);
    expect(find.text('(답장하지 않는다)'), findsNothing);
    await settle(tester);
    expect(find.text('(답장하지 않는다)'), findsNothing);
    final reopened =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    state = reopened.read(chatRoomProvider(room));
    expect(state.messages.first.isHidden, isTrue);
    expect(find.text('(답장하지 않는다)'), findsNothing);
  });
}
