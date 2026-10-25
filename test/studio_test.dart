import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_studio_client.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/features/studio/template_scenario.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 엑셀 대본 변환, 캐릭터 목록 저장, AI 생성기를 확인하는 테스트입니다.
void main() {
  group('만들기 편집기 초안', () {
    test('윤도하 시나리오를 편집기 초안으로 열었다가 저장하면 플레이 내용이 그대로', () {
      final original = loadSampleBundle();
      final back = ScenarioDraft.fromBundle(original).toBundle();

      expect(back.character.name, '윤도하');
      expect(back.character.typingSpeedMultiplier, 0.85);
      expect(back.character.worldSetting, original.character.worldSetting);
      expect(back.character.affectionStages.map((s) => s.stageLabel),
          ['편한 친구', '신경 쓰이는 친구', '친구 이상']);
      expect(back.events.map((e) => e.id), original.events.map((e) => e.id));
      expect(back.events.map((e) => e.eventType), original.events.map((e) => e.eventType));
      expect(back.events.where((e) => e.isDaily), hasLength(6));
      final goodnight = back.events.firstWhere((e) => e.id == 'special_goodnight');
      expect(goodnight.realTime!.fromHour, 22);
      expect(goodnight.realTime!.toHour, 2);
      expect(back.nodes, hasLength(original.nodes.length));

      int bubbles(ScenarioBundle b) =>
          b.nodes.values.fold(0, (sum, n) => sum + n.characterBubbles.length);
      int deltas(ScenarioBundle b) => b.nodes.values
          .expand((n) => n.choices)
          .fold(0, (sum, c) => sum + c.affectionDelta);
      expect(bubbles(back), bubbles(original));
      expect(deltas(back), deltas(original));

      // 갈림길: 공연을 거절하면 컷씬 장면을 건너뜀
      final gig = back.firstNodeOf('evt_gig_tickets')!;
      final decline = gig.choices.firstWhere((c) => c.buttonLabel.contains('거절'));
      final trigger = back.events.firstWhere((e) => e.id == 'evt_gig_tickets').cutsceneTriggerStep;
      expect(back.nodes[decline.nextNodeId]!.stepOrder, isNot(trigger));
      expect(bestPathClears(back), isTrue);
      // 단계 대신 점수로 적힌 조건도 그대로
      for (final e in original.events) {
        expect(back.affectionRangeOf(back.events.firstWhere((b) => b.id == e.id)).min,
            original.affectionRangeOf(e).min, reason: e.id);
      }
    });

    test('빈 초안에서 장면·선택지를 직접 이어 만들면 플레이할 수 있는 시나리오가 됨', () {
      final d = ScenarioDraft.blank()..name = '한결';
      expect(d.problems(), isNotEmpty); // 대사가 비어 있음
      final event = d.events.single
        ..title = '첫 라떼'
        ..cutscene = '창가 자리의 라떼';
      final second = SceneDraft(lines: [LineDraft(text: '{이름} 또 왔네요')]);
      event.scenes.first.lines.first.text = '왔어요?';
      event.scenes.first.choices.add(ChoiceDraft(label: '인사하기', messages: '안녕하세요\n오늘도 라떼요', affection: 5, next: second));
      event.scenes.add(second..cutsceneHere = true);
      d.events.add(EventDraft(id: d.newEventId(), kind: DraftKind.ending, title: '마감', scenes: [
        SceneDraft(lines: [LineDraft(text: '내일도 와요')]),
      ]));
      expect(d.problems(), isEmpty);

      final bundle = d.toBundle();
      final first = bundle.firstNodeOf(event.id)!;
      expect(first.choices.single.userBubbles.map((b) => b.text), ['안녕하세요', '오늘도 라떼요']);
      expect(bundle.nodes[first.choices.single.nextNodeId]!.characterBubbles.single.text, '{이름} 또 왔네요');
      expect(bundle.events.first.cutsceneTriggerStep, 2);
      expect(bundle.events.last.isEnding, isTrue);
      expect(bestPathClears(bundle), isTrue);

      // 장면을 지우면 그 장면으로 가던 선택지는 '대화 끝'이 됨
      event.scenes.remove(second);
      for (final c in event.scenes.first.choices) {
        if (c.next == second) c.next = null;
      }
      expect(d.toBundle().firstNodeOf(event.id)!.choices.single.nextNodeId, isNull);
    });

    test('올린 사진은 캐릭터 파일에 한 번만 저장되고, 말풍선·컷씬은 번호로 가리킴', () {
      const photo = 'data:image/jpeg;base64,AAAA';
      final d = ScenarioDraft.blank()..name = '한결';
      final event = d.events.single
        ..title = '첫 라떼'
        ..cutsceneImage = photo; // 설명 없이 사진만 올려도 컷씬이 됨
      event.scenes.first.lines
        ..first.text = '이거 봐'
        ..add(LineDraft(photoImage: photo))
        ..add(LineDraft(photo: '설명만 있는 사진'));

      final bundle = ScenarioBundle.fromJson(jsonDecode(jsonEncode(d.toBundle().toJson())) as Map<String, dynamic>);
      expect(bundle.images.length, 1); // 같은 사진은 하나로
      final bubbles = bundle.firstNodeOf(event.id)!.characterBubbles;
      expect(bubbles[1].photoImage, startsWith('img:'));
      expect(bubbles[1].photoLabel, '사진');
      expect(bundle.resolveImage(bubbles[1].photoImage), photo);
      expect(bubbles[2].photoImage, isNull);
      final e = bundle.events.first;
      expect(e.cutscenePhotoTitle, '첫 라떼');
      expect(bundle.resolveImage(e.cutsceneImageUrl), photo);

      // 대화 기록에는 사진 번호만 남음
      final log = ChatMessageLog(
        id: 'm', isUser: false, speakerCharacterId: 'c', speakerName: '한결', text: '',
        photoLabel: bubbles[1].photoLabel, photoImage: bubbles[1].photoImage, timestamp: DateTime(2026),
      );
      expect(jsonEncode(log.toJson()), isNot(contains('base64')));

      // 다시 편집기로 열면 사진이 그대로 있음
      final back = ScenarioDraft.fromBundle(bundle);
      expect(back.events.single.cutsceneImage, photo);
      expect(back.events.single.scenes.first.lines[1].photoImage, photo);
    });

    test('저장할 때 사진 자리 맞추기: 같은 설명·남은 사진 1장은 자동 연결, 못 맞춘 곳은 알려 줌', () {
      const p1 = 'data:image/png;base64,AAAA';
      const p2 = 'data:image/png;base64,BBBB';
      const p3 = 'data:image/png;base64,CCCC';
      final d = ScenarioDraft.blank()..name = '한결';
      final first = d.events.single
        ..title = '첫 라떼'
        ..cutscene = '창가 자리의 라떼'
        ..cutsceneImage = p1
        ..photos.addAll([p1, p2]);
      final sameAsCut = LineDraft(photo: '창가 자리의 라떼');
      final selfie = LineDraft(photo: '두부 셀카');
      first.scenes.first.lines.addAll([sameAsCut, selfie]);
      // 사진함에 사진 2장, 빈 자리 2곳이라 어느 게 맞는지 몰라서 못 붙임
      final second = EventDraft(id: d.newEventId(), title: '야경', photos: [p2, p3], scenes: [
        SceneDraft(lines: [LineDraft(photo: '한강 야경'), LineDraft(photo: '편의점 앞')]),
      ]);
      // 사진함에 사진은 없으면 설명 카드로 두는 거라 안 알려 줌
      final third = EventDraft(id: d.newEventId(), title: '설명만', scenes: [
        SceneDraft(lines: [LineDraft(photo: '그냥 카드')]),
      ]);
      d.events.addAll([second, third]);

      expect(d.sharedPhotoFor(first.photoSlots[1]), p1); // 같은 설명이라 플레이 땐 컷씬 사진이 나옴
      expect(d.autoLinkPhotos(), 2);
      expect(sameAsCut.photoImage, p1);
      expect(selfie.photoImage, p2); // 남은 사진 1장, 빈 자리 1곳
      final missing = d.missingPhotos();
      expect(missing.map((s) => s.label), ['한강 야경', '편의점 앞']);
      expect(missing.first.event, second);
      expect(missing.first.sceneIndex, 0);
      expect(missing.first.where, contains('장면 1'));
      expect(first.unusedPhotos, isEmpty);

      // 한 번 더 해도 그대로
      expect(d.autoLinkPhotos(), 0);
    });

    test('저장 전에 고칠 곳을 알려 줌', () {
      final d = ScenarioDraft.blank();
      d.stages.first.start = 5;
      d.events.single.kind = DraftKind.special;
      d.events.single.date = '크리스마스';
      final problems = d.problems().join('\n');
      expect(problems, contains('[캐릭터] 이름'));
      expect(problems, contains('0점부터'));
      expect(problems, contains('호감도 이벤트를 하나 이상'));
      expect(problems, contains('12-25처럼'));
    });

    test('특별 이벤트 시간 구간은 자정을 넘겨도 맞게 판단', () {
      const night = RealTimeWindow(fromHour: 22, toHour: 2);
      expect(night.contains(DateTime(2026, 1, 1, 23)), isTrue);
      expect(night.contains(DateTime(2026, 1, 1, 1)), isTrue);
      expect(night.contains(DateTime(2026, 1, 1, 2)), isFalse);
      expect(night.contains(DateTime(2026, 1, 1, 15)), isFalse);
      const xmas = RealTimeWindow(date: '12-25');
      expect(xmas.contains(DateTime(2026, 12, 25, 9)), isTrue);
      expect(xmas.contains(DateTime(2026, 12, 24, 9)), isFalse);
      expect(night.label, '밤 10시~새벽 2시');
    });

    test('{이름} 뒤 조사는 별명 받침에 맞게 바뀜', () {
      String fill(String t, String n) => CharacterModel.fillUserName(t, n);
      expect(fill('{이름}아 뭐해', '쨋뀨'), '쨋뀨야 뭐해');
      expect(fill('{이름}아 뭐해', '서연'), '서연아 뭐해');
      expect(fill('{이름}이 그랬잖아', '쨋뀨'), '쨋뀨가 그랬잖아');
      expect(fill('{이름}이랑 갈래', '쨋뀨'), '쨋뀨랑 갈래');
      expect(fill('{이름}은 어때', '서연'), '서연은 어때');
      expect(fill('{이름}. 그리고 {이름}', 'Lia'), 'Lia. 그리고 Lia');
    });

    test('{{user}}·{{char}}도 이름으로 바뀌고 조사가 맞춰짐', () {
      String fill(String t) => CharacterModel.fillUserName(t, '쨋뀨', charName: '카이엔');
      expect(fill('{{user}}아, {{char}}이 기다려'), '쨋뀨야, 카이엔이 기다려');
      expect(fill('{{char}}와 {{user}}는 비밀 친구'), '카이엔과 쨋뀨는 비밀 친구');
      expect(fill('{{ User }}랑 {이름}'), '쨋뀨랑 쨋뀨');
      // charName을 안 주면 {{char}}는 그대로
      expect(CharacterModel.fillUserName('{{char}}', '쨋뀨'), '{{char}}');
      // AI에게 넘기는 설정은 {{char}}만 채우고 {{user}}는 남김 (자유대화에서 별명으로 채움)
      const c = CharacterModel(
        id: 'c', creatorId: 'u', name: '도하', statusMessage: '', avatarUrl: '',
        worldviewPrompt: '{{char}}는 {{user}}의 남사친이다.', affectionStages: [],
      );
      expect(c.aiCharacterSheet, '도하는 {{user}}의 남사친이다.');
    });

    test('AI에게 넘기는 설정에는 세계관·비밀·유저 설정까지 들어감', () {
      final sheet = loadSampleBundle().character.aiCharacterSheet;
      expect(sheet, contains('새벽녘 라디오'));
      expect(sheet, contains('세계관: 지금의 서울'));
      expect(sheet, contains('비밀(유저는 아직 모름'));
      expect(sheet, contains('유저 설정: {이름} · 1년 전'));
      expect(sheet, contains('준혁 (도하의 룸메이트'));
      expect(sheet, contains('진짜 마음 처음 팀플 하던 날부터 좋아했음(비밀)'));
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
      // 친구 목록엔 있지만 대화방은 별명을 정하고 대화를 시작해야 생김
      expect(container.read(chatRoomsProvider), isEmpty);

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
      expect(container.read(chatRoomsProvider), ['char_example_seo_ijun']);

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
          character: CharacterModel(
            id: 'draft',
            creatorId: 'me',
            name: '한결',
            statusMessage: '바리스타',
            avatarUrl: '',
            worldviewPrompt: '무뚝뚝하지만 다정한 카페 사장. 말끝을 흐린다.',
            userRole: '단골 카페 사장님',
            secret: '사실 카페를 접으려다 너 때문에 버티는 중',
            typingSpeedMultiplier: 1.3,
            affectionStages: [
              AffectionStage(minScore: 0, maxScore: 29, stageLabel: '손님'),
              AffectionStage(minScore: 30, maxScore: 100, stageLabel: '단골'),
            ],
          ),
          eventsPerStage: 1,
          dailiesPerStage: 1,
          specials: 1,
        ),
        onProgress: (message, done, total) => progress.add('$done/$total'),
      );

      expect(adapter.calls, 1 + 6); // 목차 1번 + 대화 6개
      expect(adapter.bodies.first['output_config']['format']['schema']['properties']['talks']
          ['items']['properties']['stage']['enum'], ['손님', '단골']);
      expect(adapter.bodies.first['messages'][0]['content'], contains('단골 카페 사장님'));
      expect(progress.last, '7/7');

      expect(bundle.character.name, '한결');
      expect(bundle.character.typingSpeedMultiplier, 1.3);
      // 목차와 함께 받은 캐릭터 설정 카드
      expect(bundle.character.tagline, '말없이 라떼를 내미는 사장님');
      expect(bundle.character.quote, '…오늘도 그거죠?');
      expect(bundle.character.profileFields.map((f) => f.label), ['나이', '직업']);
      expect(bundle.character.traits.single.percent, 30);
      expect(bundle.character.sampleQuotes, hasLength(1));
      expect(bundle.character.userRole, '단골 카페 사장님');
      expect(bundle.character.secret, contains('버티는 중'));
      expect(bundle.character.id, startsWith('char_'));
      // 대사 요청에는 AI가 채운 설정과 비밀이 같이 들어감
      expect(adapter.bodies[1]['messages'][0]['content'], allOf(contains('…오늘도 그거죠?'), contains('버티는 중')));
      expect(bundle.events.map((e) => e.eventType), [
        ScenarioEventType.autoStory, ScenarioEventType.daily,
        ScenarioEventType.autoStory, ScenarioEventType.daily, ScenarioEventType.special,
        ScenarioEventType.ending,
      ]);
      final special = bundle.events[4];
      expect(special.realTime!.fromHour, 23);
      expect(special.timeNotice, isNull); // 특별 이벤트는 장면 전환 문구 없이 바로
      expect(bundle.events.first.timeNotice, '다음 날');
      expect(bundle.character.worldSetting, '골목 끝 작은 카페');
      expect(bundle.character.id, isNot('draft'));
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
            'tagline': '말없이 라떼를 내미는 사장님',
            'tags': ['카페', '무뚝뚝'],
            'world_setting': '골목 끝 작은 카페',
            'quote': '…오늘도 그거죠?',
            'profile_fields': [
              {'label': '나이', 'value': '29살'},
              {'label': '직업', 'value': '카페 사장'},
            ],
            'traits': [
              {'left': '내향', 'right': '외향', 'percent': 30},
            ],
            'sample_quotes': [
              {'situation': '바쁠 때', 'body': '…잠깐만요.'},
            ],
            'talks': [
              _talk('event', '손님', '첫 라떼', '두 잔째 라떼를 건네는 한결'),
              _talk('daily', '손님', '비 오는 오후', ''),
              _talk('event', '단골', '마감 후', ''),
              _talk('daily', '단골', '새 원두', ''),
              {..._talk('special', '단골', '마감 후 새벽 톡', ''), 'from_hour': 23, 'to_hour': 3},
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
        'time_notice': '다음 날',
        'synopsis': '$title 이야기',
        'cutscene': cutscene,
        'from_hour': 0,
        'to_hour': 0,
      };

  @override
  void close({bool force = false}) {}
}
