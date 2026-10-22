import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_studio_client.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/studio/script_workbook.dart';
import 'package:mallangtalk/features/studio/template_scenario.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 엑셀 대본 변환, 캐릭터 목록 저장, AI 생성기를 확인하는 테스트입니다.
void main() {
  group('엑셀 대본', () {
    test('윤도하 대본을 엑셀로 내보냈다가 다시 읽으면 내용이 그대로', () {
      final original = loadSampleBundle();
      final result = ScriptWorkbook.decode(ScriptWorkbook.encode(original));
      final back = result.bundle;

      expect(back.character.name, '윤도하');
      expect(back.character.typingSpeedMultiplier, 0.85);
      expect(back.character.affectionStages.map((s) => s.stageLabel),
          ['편한 친구', '신경 쓰이는 친구', '친구 이상']);
      expect(back.events.map((e) => e.id), original.events.map((e) => e.id));
      expect(back.events.where((e) => e.isDaily), hasLength(8));
      expect(back.events.firstWhere((e) => e.id == 'daily_rain').stageLabel, '편한 친구');
      expect(back.nodes, hasLength(original.nodes.length));

      int bubbles(ScenarioBundle b) =>
          b.nodes.values.fold(0, (sum, n) => sum + n.characterBubbles.length);
      int deltas(ScenarioBundle b) => b.nodes.values
          .expand((n) => n.choices)
          .fold(0, (sum, c) => sum + c.affectionDelta);
      expect(bubbles(back), bubbles(original));
      expect(deltas(back), deltas(original));

      // 갈림길: 공연을 거절하면 3단계 '거절' 장면으로 가고 컷씬(2단계)은 못 봄
      final gig = back.firstNodeOf('evt_gig_tickets')!;
      final decline = gig.choices.firstWhere((c) => c.buttonLabel.contains('거절'));
      expect(back.nodes[decline.nextNodeId]!.stepOrder, 3);
      expect(back.events.firstWhere((e) => e.id == 'evt_gig_tickets').cutsceneTriggerStep, 2);
      expect(bestPathClears(back), isTrue);
    });

    test('템플릿(예시 캐릭터)은 바로 올려도 끝까지 플레이할 수 있음', () {
      final result = ScriptWorkbook.decode(ScriptWorkbook.encode(templateScenario()));
      expect(result.bundle.character.name, '서이준');
      expect(result.bundle.events.where((e) => e.isDaily), hasLength(2));
      expect(result.bundle.events.where((e) => e.isEnding), hasLength(1));
      expect(result.warnings, isEmpty);
      expect(bestPathClears(result.bundle), isTrue);
      // 사진만 있는 말풍선, 이름 붙인 장면(2-거절)도 그대로
      final film = result.bundle.firstNodeOf('daily_film')!;
      expect(film.characterBubbles.last.photoLabel, contains('필름 사진'));
      expect(result.bundle.nodes.containsKey('evt_photo_walk_2-거절'), isTrue);
    });

    test('잘못 쓴 곳은 시트 이름과 줄 번호로 알려줌', () {
      final broken = ScenarioBundle(
        character: templateScenario().character,
        events: [
          ...templateScenario().events.map((e) => e.id == 'evt_rainy_cafe'
              ? ScenarioEventModel(
                  id: e.id,
                  characterId: e.characterId,
                  chapterOrder: e.chapterOrder,
                  eventType: e.eventType,
                  title: e.title,
                  stageLabel: '없는 단계',
                )
              : e),
        ],
        nodes: templateScenario().nodes,
      );
      expect(
        () => ScriptWorkbook.decode(ScriptWorkbook.encode(broken)),
        throwsA(isA<ScriptWorkbookException>().having(
          (e) => e.errors.join(),
          'errors',
          allOf(contains('[이벤트] 4번째 줄'), contains('없는 단계')),
        )),
      );
      expect(
        () => ScriptWorkbook.decode(Uint8List.fromList(utf8.encode('엑셀 아님'))),
        throwsA(isA<ScriptWorkbookException>()),
      );
    });

    test('저장소에 템플릿 파일이 최신 내용으로 들어 있음', () {
      final file = File('templates/mallangtalk_script_template.xlsx');
      expect(file.existsSync(), isTrue, reason: 'tool/make_template.dart로 만들어 둬야 함');
      final result = ScriptWorkbook.decode(file.readAsBytesSync());
      expect(result.bundle.character.name, templateScenario().character.name);
      expect(result.bundle.nodes.length, templateScenario().nodes.length);
    });
  });

  group('내 캐릭터 목록', () {
    test('처음엔 기본 캐릭터가 있고, 추가·삭제가 새로고침 후에도 남음', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer open() {
        final container = ProviderContainer(overrides: [
          builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
        ]);
        addTearDown(container.dispose);
        return container;
      }

      var container = open();
      await container.read(builtinBundlesProvider.future);
      await container.read(sharedPreferencesProvider.future);
      expect(container.read(characterLibraryProvider).map((e) => e.id), [dohaId]);
      expect(container.read(chatRoomsProvider), [dohaId]);

      await container.read(characterLibraryProvider.notifier)
          .add(templateScenario(), CharacterSource.created);
      container.read(chatRoomsProvider.notifier).open('char_example_seo_ijun');

      container = open();
      await container.read(builtinBundlesProvider.future);
      await container.read(sharedPreferencesProvider.future);
      final entries = container.read(characterLibraryProvider);
      expect(entries.map((e) => e.id), [dohaId, 'char_example_seo_ijun']);
      expect(entries.last.source, CharacterSource.created);
      expect(entries.last.bundle.events, hasLength(5));
      expect(container.read(chatRoomsProvider), ['char_example_seo_ijun', dohaId]);

      await container.read(characterLibraryProvider.notifier).remove(dohaId);
      container = open();
      await container.read(builtinBundlesProvider.future);
      await container.read(sharedPreferencesProvider.future);
      expect(container.read(characterLibraryProvider).map((e) => e.id), ['char_example_seo_ijun']);
      expect(container.read(chatRoomsProvider), ['char_example_seo_ijun']);
    });
  });

  group('AI로 만들기', () {
    test('목차 → 대화별 대사 순서로 부르고, 끝까지 갈 수 있게 호감도를 맞춤', () async {
      final adapter = _ScriptedAdapter();
      final client = ClaudeStudioClient(
        dio: Dio(BaseOptions(baseUrl: 'https://api.anthropic.com'))..httpClientAdapter = adapter,
      );
      final progress = <String>[];
      final bundle = await client.generate(
        apiKey: 'sk-ant-xyz',
        model: 'claude-sonnet-5-5',
        brief: const StudioBrief(
          name: '한결',
          statusMessage: '바리스타',
          personality: '무뚝뚝하지만 다정한 카페 사장. 말끝을 흐린다.',
          relationship: '단골 카페 사장님',
          typingSpeedMultiplier: 1.3,
          stages: [
            AffectionStage(minScore: 0, maxScore: 29, stageLabel: '손님'),
            AffectionStage(minScore: 30, maxScore: 100, stageLabel: '단골'),
          ],
          eventsPerStage: 1,
          dailiesPerStage: 1,
        ),
        onProgress: (message, done, total) => progress.add('$done/$total'),
      );

      expect(adapter.calls, 1 + 5); // 목차 1번 + 대화 5개
      expect(adapter.bodies.first['output_config']['format']['schema']['properties']['talks']
          ['items']['properties']['stage']['enum'], ['손님', '단골']);
      expect(adapter.bodies.first['messages'][0]['content'], contains('단골 카페 사장님'));
      expect(progress.last, '6/6');

      expect(bundle.character.name, '한결');
      expect(bundle.character.typingSpeedMultiplier, 1.3);
      expect(bundle.events.map((e) => e.eventType), [
        ScenarioEventType.autoStory, ScenarioEventType.daily,
        ScenarioEventType.autoStory, ScenarioEventType.daily, ScenarioEventType.ending,
      ]);
      expect(bundle.events[2].stageLabel, '단골');
      expect(bundle.events.first.cutsceneTriggerStep, 2);
      expect(bundle.events[1].cutsceneTriggerStep, isNull); // 일상 대화엔 컷씬 없음
      final first = bundle.firstNodeOf(bundle.events.first.id)!;
      expect(first.choices.first.nextNodeId, '${bundle.events.first.id}_2');
      // 대본의 점수(+3)만으로는 '단골'(30점)에 못 가서 자동으로 올려 맞춤
      expect(bestPathClears(bundle), isTrue);
      expect(first.choices.first.affectionDelta, greaterThan(3));
    });
  });
}

/// 목차 요청에는 목차를, 대사 요청에는 장면 2개짜리 대본을 돌려주는 가짜 서버
class _ScriptedAdapter implements HttpClientAdapter {
  int calls = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    final body = options.data as Map<String, dynamic>;
    bodies.add(body);
    final isOutline = (body['output_config']['format']['schema']['properties'] as Map)
        .containsKey('talks');
    final payload = isOutline
        ? {
            'talks': [
              _talk('event', '손님', '첫 라떼', '두 잔째 라떼를 건네는 한결'),
              _talk('daily', '손님', '비 오는 오후', ''),
              _talk('event', '단골', '마감 후', ''),
              _talk('daily', '단골', '새 원두', ''),
              _talk('ending', '단골', '간판 불 끄고', ''),
            ],
          }
        : {
            'scenes': [
              {
                'scene': '1',
                'step': 1,
                'lines': [
                  {'text': '왔어요?', 'speed': 0.8, 'photo': ''},
                  {'text': '오늘은', 'speed': 1.4, 'photo': ''},
                ],
                'choices': [
                  {'label': '반갑게 인사하기', 'user_messages': ['안녕하세요!'], 'affection': 3, 'next_scene': '2'},
                  {'label': '그냥 주문하기', 'user_messages': ['아메리카노요'], 'affection': 0, 'next_scene': ''},
                ],
              },
              {
                'scene': '2',
                'step': 2,
                'lines': [
                  {'text': '...반가워요', 'speed': 1.5, 'photo': '창가 자리에 놓인 라떼 사진'},
                ],
                'choices': [],
              },
            ],
            'cutscene_step': 2,
          };
    return ResponseBody.fromString(
      jsonEncode({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(payload)},
        ],
      }),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  static Map<String, dynamic> _talk(String kind, String stage, String title, String cutscene) => {
        'kind': kind,
        'stage': stage,
        'title': title,
        'time_notice': '화요일 오후 3:00',
        'synopsis': '$title 이야기',
        'cutscene': cutscene,
      };

  @override
  void close({bool force = false}) {}
}
