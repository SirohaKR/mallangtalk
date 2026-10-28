import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:mallangtalk/shared/widgets/inline_image_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'test_helpers.dart';

void main() {
  testWidgets(
      'legacy duplicate message IDs remain distinct when a new message is added',
      (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(SavedRun(
          affection: 0,
          flags: const [],
          completedEventIds: const [],
          messages: [
            ChatMessageLog(
                id: 'legacy_duplicate',
                isUser: false,
                speakerCharacterId: dohaId,
                speakerName: '캐릭터',
                text: '지난 첫 말',
                timestamp: DateTime(2026)),
            ChatMessageLog(
                id: 'legacy_duplicate',
                isUser: false,
                speakerCharacterId: dohaId,
                speakerName: '캐릭터',
                text: '지난 다음 말',
                timestamp: DateTime(2026)),
          ]).toJson()),
    });
    final container =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container
        .read(chatRoomProvider(room).notifier)
        .sendUserMessage(text: '새 말');
    await settle(tester);
    expect(find.text('지난 첫 말'), findsOneWidget);
    expect(find.text('지난 다음 말'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('inline image buffers are reused and the cache evicts old entries', () {
    final cache = InlineImageCache(maxEntries: 1);
    const a = 'data:image/png;base64,AA==';
    const b = 'data:image/png;base64,AQ==';
    final first = cache.providerFor(a);
    expect(cache.providerFor(a), same(first));
    cache.providerFor(b);
    expect(cache.providerFor(a), isNot(same(first)));
    expect(cache.providerFor('data:image/png;base64,invalid!'), isNull);
  });
  testWidgets(
      'new messages and typing preserve the existing photo image and element',
      (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container =
        await openDohaChat(tester, roomId: room, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = container.read(chatRoomProvider(room).notifier);
    final image =
        'data:image/png;base64,${base64Encode(File('web/icons/Icon-192.png').readAsBytesSync())}';
    notifier.sendUserMessage(
        text: '사진', photoLabel: '첨부한 사진', photoImage: image);
    await settle(tester);
    final finder = find
        .byWidgetPredicate((w) => w is Image && w.semanticLabel == '첨부한 사진');
    expect(finder, findsOneWidget);
    final element = tester.element(finder);
    final provider = tester.widget<Image>(finder).image;
    notifier.sendUserMessage(text: '그리고 오늘은?');
    await tester.pump();
    expect(tester.element(finder), same(element));
    expect(tester.widget<Image>(finder).image, same(provider));
    await tester.pump(const Duration(milliseconds: 2600));
    expect(tester.element(finder), same(element));
    expect(tester.widget<Image>(finder).gaplessPlayback, isTrue);
    await settle(tester);
    expect(tester.element(finder), same(element));
  });
  testWidgets('quoted text has readable contrast in a dark outgoing bubble',
      (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final base = loadSampleBundle();
    const dark = Color(0xFF201C2F);
    final bundle = ScenarioBundle(
        character: base.character
            .copyWith(themeColor: '#201C2F', bubbleStyle: 'theme'),
        events: base.events,
        nodes: base.nodes,
        images: base.images);
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(tester,
        roomId: room, bundle: bundle, extra: testAiOverrides);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = container.read(chatRoomProvider(room).notifier);
    notifier.sendUserMessage(text: '인용 원문');
    await settle(tester);
    final target = container.read(chatRoomProvider(room)).messages.first;
    notifier.sendUserMessage(text: '내 답장', replyTo: target);
    await settle(tester);
    final reply = container
        .read(chatRoomProvider(room))
        .messages
        .singleWhere((m) => m.text == '내 답장');
    final quote = find.byKey(ValueKey('quoted_${reply.id}'));
    final text = tester
        .widget<Text>(find.descendant(of: quote, matching: find.byType(Text)));
    final decoration =
        tester.widget<Container>(quote).decoration as BoxDecoration;
    final background =
        Color.alphaBlend(decoration.color!, dark).computeLuminance();
    final foreground = text.style!.color!.computeLuminance();
    expect(
        (math.max(background, foreground) + 0.05) /
            (math.min(background, foreground) + 0.05),
        greaterThan(4.5));
  });
}
