import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/core/network/conversation_context.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';

/// 로어북(키워드가 나올 때만 넘기는 설정)과 옛 기억 꺼내기 테스트
void main() {
  const luna = LoreEntry(keys: ['루나', 'Cat'], content: '루나는 {{char}}의 3살 고양이. {{user}}가 좋아함');
  const always = LoreEntry(content: '왼손잡이', always: true);
  const cafe = LoreEntry(keys: ['카페'], content: '단골 카페는 망원동 소금빵집');

  test('키워드가 나온 항목과 항상 기억 항목만 고름', () {
    expect(LoreEntry.pick([luna, always, cafe], '오늘 루나 밥 줬어?'), [always, luna]);
    expect(LoreEntry.pick([luna, cafe], 'my CAT is cute'), [luna]); // 영어는 대소문자 무시
    expect(LoreEntry.pick([luna, cafe], '뭐 해'), isEmpty);
    expect(LoreEntry.pick([luna, cafe, always], '루나랑 카페', limit: 2), [always, luna]);
  });

  test('JSON으로 저장했다 다시 읽어도 같음', () {
    const c = CharacterModel(
      id: 'c', creatorId: 'u', name: '윤도하', statusMessage: '', avatarUrl: '',
      worldviewPrompt: '남사친', affectionStages: [], lorebook: [luna, always],
    );
    final back = CharacterModel.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.lorebook.map((e) => e.toJson()), [luna.toJson(), always.toJson()]);
    expect(const CharacterModel(
      id: 'c', creatorId: 'u', name: '', statusMessage: '', avatarUrl: '',
      worldviewPrompt: '', affectionStages: [],
    ).toJson().containsKey('lorebook'), isFalse);
  });

  test('편집기 초안: 쉼표 키워드를 나누고 빈 항목은 버림', () {
    final d = ScenarioDraft.fromBundle(ScenarioBundle(
      character: const CharacterModel(
        id: 'c', creatorId: 'u', name: '윤도하', statusMessage: '', avatarUrl: '',
        worldviewPrompt: '남사친', affectionStages: [], lorebook: [luna],
      ),
      events: const [], nodes: const {},
    ));
    expect(d.lore.single.keys, '루나, Cat');
    d.lore
      ..add(LoreDraft(keys: ' 카페 ,, 빵 ', content: ' 소금빵 '))
      ..add(LoreDraft(keys: '키워드만'))
      ..add(LoreDraft(content: '키워드 없음'));
    final built = d.buildCharacter().lorebook;
    expect(built.length, 2);
    expect(built[1].keys, ['카페', '빵']);
    expect(built[1].content, '소금빵');
  });

  test('옛 기억은 최근 5개 + 지금 대화와 같은 낱말이 나온 것만', () {
    final memories = [
      '쨋뀨랑 망원동 소금빵 맛집 얘기를 했다',
      '쨋뀨가 시험 망쳐서 위로해 줬다',
      '같이 오늘 이야기를 나눴다',
      for (var i = 1; i <= 5; i++) '최근 기억 $i',
    ];
    final got = recallMemories(memories, '소금빵 또 먹고 싶다', ignore: {'쨋뀨'});
    expect(got.first, memories.first);
    expect(got.length, 6);
    // 이름·흔한 말만 겹치면 안 꺼냄
    expect(recallMemories(memories, '쨋뀨 오늘 뭐 해', ignore: {'쨋뀨'}).length, 5);
    // 조사를 떼고 비교 (시험이 → 시험)
    expect(recallMemories(memories, '나 시험 끝났어', ignore: {'쨋뀨'}), contains(memories[1]));
  });

  test('자유대화 요청에 관련 로어북과 기억이 들어감', () async {
    final adapter = _FakeAdapter({
      'content': [{'type': 'text', 'text': jsonEncode({'replies': ['루나 자'], 'affection_delta': 0})}],
    });
    await ClaudeChatClient(dio: Dio()..httpClientAdapter = adapter).reply(
      apiKey: 'k',
      model: 'claude-opus-5-5',
      character: const CharacterModel(
        id: 'c', creatorId: 'u', name: '윤도하', statusMessage: '', avatarUrl: '',
        worldviewPrompt: '남사친', affectionStages: [], lorebook: [luna, cafe],
      ),
      stageLabel: null,
      currentEventTitle: null,
      history: const [],
      newUserMessages: ['루나 뭐 해?'],
      userName: '쨋뀨',
      memories: ['루나 사진을 보내 줬다', '1', '2', '3', '4', '5'],
    );
    final system = adapter.body!['system'].toString();
    expect(system, contains('루나는 윤도하의 3살 고양이. 쨋뀨가 좋아함'));
    expect(system, isNot(contains('소금빵')));
    expect(system, contains('- 루나 사진을 보내 줬다'));
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.response);
  final Map<String, dynamic> response;
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    body = options.data as Map<String, dynamic>;
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
