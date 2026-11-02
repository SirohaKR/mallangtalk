import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/scene/scene_room.dart';
import 'package:mallangtalk/features/scene/scene_screen.dart';
import 'package:mallangtalk/features/settings/byok_settings.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 현실 장면 방: 톡 말풍선 꾹 → 현실 장면으로, 소설형 장면, 톡 방과 로어북 같이 씀
void main() {
  test('지문은 괄호, 대사는 따옴표로 바꿈 (주변 인물은 이름 붙임)', () {
    final text = ClaudeChatClient.formatSceneSegments([
      {'kind': 'narration', 'speaker': '', 'text': '도하가 고개를 들었다.'},
      {'kind': 'dialogue', 'speaker': '윤도하', 'text': '"왔어?"'},
      {'kind': 'dialogue', 'speaker': '점원', 'text': '주문하시겠어요?'},
      {'kind': 'narration', 'speaker': '', 'text': '(바람이 불었다)'},
    ], '윤도하');
    expect(text, '(도하가 고개를 들었다.)\n"왔어?"\n점원 "주문하시겠어요?"\n(바람이 불었다)');
  });

  test('괄호 안은 지문 색, 밖은 대사 색', () {
    const narration = Color(0xFF111111);
    const dialogue = Color(0xFF222222);
    final span = sceneTextSpan('(웃었다) "안녕" (손을 흔들었다)', narration: narration, dialogue: dialogue);
    final parts = [for (final c in span.children!) (c as TextSpan)];
    expect(parts.map((p) => p.text), ['(웃었다)', ' "안녕" ', '(손을 흔들었다)']);
    expect(parts.map((p) => p.style!.color), [narration, dialogue, narration]);
  });

  test('답이 1900자보다 짧으면 이어 쓰게 해서 늘 1900자 이상', () async {
    final adapter = _SceneAdapter([800, 800, 800]);
    final client = ClaudeChatClient(dio: Dio()..httpClientAdapter = adapter);
    final text = await client.sceneTurn(
      apiKey: 'k',
      model: 'm',
      character: loadSampleBundle().character,
      userName: '쨋뀨',
      talkContext: '쨋뀨: 지금 나와',
      scene: const [],
      userInput: null,
    );
    expect(adapter.calls, 3);
    expect(text.length, greaterThanOrEqualTo(ClaudeChatClient.sceneMinChars));
    expect(adapter.lastUser, contains('모자라다'));
    expect(adapter.firstSystem, contains('1900자 이상'));
  });

  testWidgets('톡을 꾹 눌러 현실 장면으로 → 그 톡까지가 장면 맥락, 장면을 마치면 요약이 톡 방 로어북에', (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'run_$room': jsonEncode(SavedRun(
        affection: 0,
        flags: const [],
        completedEventIds: const [],
        messages: [
          ChatMessageLog(id: 'a', isUser: true, speakerCharacterId: 'user', speakerName: '쨋뀨', text: '편의점 앞이야', timestamp: DateTime(2026)),
          ChatMessageLog(id: 'b', isUser: false, speakerCharacterId: dohaId, speakerName: '윤도하', text: '금방 갈게', timestamp: DateTime(2026)),
          ChatMessageLog(id: 'c', isUser: true, speakerCharacterId: 'user', speakerName: '쨋뀨', text: '나중 톡', timestamp: DateTime(2026)),
        ],
        memories: const ['옛 기억'],
      ).toJson()),
    });
    final fake = _SceneFake();
    final container = await openDohaChat(tester, roomId: room, extra: [
      byokSettingsProvider.overrideWith(_Ai.new),
      claudeChatClientProvider.overrideWithValue(fake),
    ]);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.longPress(find.text('금방 갈게'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('msg_reply')), findsOneWidget);
    // 대화방은 라우터 없이 띄워서, 메뉴 고르기 대신 notifier로 장면을 시작
    Navigator.of(tester.element(find.byKey(const ValueKey('msg_scene')))).pop();
    await tester.pumpAndSettle();
    await container.read(sceneRoomProvider(room).notifier).startFrom('b');
    await tester.pump();

    expect(fake.contexts.single, contains('금방 갈게'));
    expect(fake.contexts.single, isNot(contains('나중 톡')));
    expect(fake.memories.single, ['옛 기억']); // 톡 방 로어북을 같이 씀

    // 장면 방 화면
    Navigator.of(tester.element(find.text('금방 갈게')))
        .push(MaterialPageRoute<void>(builder: (_) => SceneScreen(sourceRoomId: room)));
    await tester.pumpAndSettle();
    expect(find.textContaining('도하가 편의점 앞에 섰다', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('scene_cost')), findsOneWidget);
    expect(find.textContaining('보내면 약'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('scene_input')), '(손을 흔든다) 여기야!');
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    expect(fake.inputs.last, '(손을 흔든다) 여기야!');

    await container.read(sceneRoomProvider(room).notifier).endScene();
    await tester.pumpAndSettle();
    final memories = container.read(chatRoomProvider(room)).memories;
    expect(memories, ['옛 기억', '현실 · 편의점 앞\n편의점 앞에서 만났다']);
    expect(container.read(localStoreProvider).loadRun(room)!.memories, memories);
    expect(container.read(localStoreProvider).loadScene(room), isNotNull);
    expect(container.read(sceneRoomProvider(room)).sceneOpen, isFalse);

    // 다시 열어도 장면 기록이 남아 있음 (scene_ 키, 기기 연동 대상)
    expect(LocalStore.isSyncedKey('scene_$room'), isTrue);
    final reopened = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
      builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
    ]);
    addTearDown(reopened.dispose);
    await reopened.read(sharedPreferencesProvider.future);
    await reopened.read(builtinBundlesProvider.future);
    expect(reopened.read(sceneRoomProvider(room)).lines.where((l) => l.isStory), hasLength(2));
  });
}

class _Ai extends ByokSettingsNotifier {
  @override
  ByokSettings build() => const ByokSettings(apiKey: 'test-key', model: 'claude-sonnet-5-5');
}

class _SceneFake extends ClaudeChatClient {
  _SceneFake() : super(dio: Dio());
  final contexts = <String>[];
  final memories = <List<String>>[];
  final inputs = <String?>[];

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
    contexts.add(talkContext);
    this.memories.add(memories);
    inputs.add(userInput);
    return userInput == null ? '(도하가 편의점 앞에 섰다.)\n"기다렸지?"' : '(도하가 웃었다.)\n"보여."';
  }

  @override
  Future<MemoryNote> summarizeLore({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required List<ChatMessageLog> messages,
    required String userName,
    List<String> previous = const [],
  }) async =>
      const MemoryNote(title: '편의점 앞', detail: '편의점 앞에서 만났다');
}

/// 장면 답을 정해 둔 길이만큼 돌려주는 가짜 Claude API
class _SceneAdapter implements HttpClientAdapter {
  _SceneAdapter(this.lengths);
  final List<int> lengths;
  int calls = 0;
  String lastUser = '';
  String firstSystem = '';

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
    final body = options.data is String ? jsonDecode(options.data as String) : options.data;
    final msgs = (body as Map)['messages'] as List;
    lastUser = jsonEncode(msgs.last);
    if (calls == 0) firstSystem = jsonEncode(body['system']);
    final n = lengths[calls.clamp(0, lengths.length - 1)];
    calls++;
    return ResponseBody.fromString(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {
              'type': 'text',
              'text': jsonEncode({
                'segments': [
                  {'kind': 'narration', 'speaker': '', 'text': '가' * n},
                ]
              })
            }
          ]
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}
