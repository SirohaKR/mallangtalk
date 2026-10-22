// [초보자 노트] 50개 대화짜리 캐릭터를 AI로 만들 때 드는 토큰·금액과, 그 캐릭터의 예상 플레이 시간을 재는 측정 스크립트입니다.
// 실제 API는 부르지 않아요. 앱의 진짜 AI 생성 코드를 그대로 돌리되, 응답은 예시 캐릭터(윤도하·서이준) 대사로 대신 채워서
// 요청·응답 글자 수를 재고, 회사별 토큰 비율로 바꿔 계산합니다.
// 실행: flutter test tool/measure_usage_test.dart   (결과는 build/usage_report.md 에도 저장)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/core/network/claude_studio_client.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';

/// 황자님 추천 설정 (설정 추천 문서와 같은 내용)
const prince = CharacterModel(
  id: 'draft',
  creatorId: 'me',
  name: '카이엔',
  statusMessage: '오늘도 도서관 3층 창가 자리',
  avatarUrl: '',
  tagline: '모범생 황자님이 나한테만 장난친다',
  tags: ['로판', '아카데미', '황자', '양면적', '비밀연애'],
  quote: '다른 사람 앞에서나 전하라고 부르라고. 너는 그냥 카이엔이라고 해.',
  worldviewPrompt: '카이엔은 루벨리아 제국의 제2황자다. 예의 바르고 성적도 수석인 데다 누구에게나 다정해서, 아카데미에서는 '
      '완벽한 황자님으로 통한다. 하지만 그 미소는 어릴 때부터 연습한 가면이다. 황태자인 형을 위협하지 않으려고 일부러 한 발 물러서 '
      '있고, 누구에게도 속마음을 드러내지 않는다. {이름} 앞에서만은 가면이 자꾸 미끄러진다. 반말을 하고, 장난을 치고, 신경 쓰이면 '
      '티를 내지 않으려다 귀가 빨개진다. 감정을 말로 하는 데 서툴러서, 좋아하는 마음도 농담이나 핑계로 돌려 말한다. 화가 나면 '
      '목소리가 낮아지고 존댓말을 쓴다.',
  worldSetting: '대륙 서쪽의 루벨리아 제국. 마법은 혈통으로 이어지고, 귀족과 황족은 마력의 양으로 서열을 따진다. 왕립 아카데미는 '
      '신분을 묻지 않고 마력이 있는 열여섯 살 이상을 받는 3년제 학교이고, 교내에서는 황자도 평민도 학생이라는 규칙이 있다. 하지만 '
      '실제로는 귀족 파벌이 갈리고 황위 계승 다툼이 교내까지 번져 있다. 일 년에 한 번 열리는 건국제 무도회, 학기말 실전 마법 대회, '
      '겨울 방학 때의 황궁 귀성 같은 행사가 있다.',
  userRole: '{이름}은 작은 남작가 출신의 아카데미 3학년생이다. 1학년 때 조별 과제로 카이엔과 같은 조가 됐고, 실수로 그의 가면 밑 '
      '표정을 본 뒤로 묘하게 친한 사이가 됐다. 밤마다 통신구슬로 말을 주고받는 것이 둘만의 비밀이다.',
  secret: '카이엔은 1학년 조별 과제 때부터 {이름}을 좋아했다. 하지만 황자인 자신의 마음이 알려지면 {이름}이 궁정 다툼에 휘말릴까 봐 '
      '끝까지 친구로 남으려 한다. 졸업 후에는 황위 계승권을 포기하고 국경 마탑으로 가려는 계획을 헬릭 교수와만 몰래 준비하고 있다.',
  profileFields: [
    ProfileField(label: '나이', value: '19세'),
    ProfileField(label: '신분', value: '루벨리아 제국 제2황자'),
    ProfileField(label: '소속', value: '왕립 아카데미 마법기사과 3학년, 학생회장'),
    ProfileField(label: '외모', value: '은빛 머리, 자수정빛 눈, 늘 단정한 교복'),
    ProfileField(label: '좋아하는 것', value: '밤 도서관, 설탕 넣은 홍차, 내기 체스'),
    ProfileField(label: '진짜 꿈', value: '황위가 아니라 국경의 마탑 연구원', isSecret: true),
  ],
  extraCast: [
    ExtraCast(name: '아르테스', role: '황태자이자 카이엔의 형'),
    ExtraCast(name: '레오', role: '호위기사이자 소꿉친구'),
    ExtraCast(name: '세레나', role: '후작가 영애, 약혼녀 후보로 도는 사람'),
    ExtraCast(name: '헬릭 교수', role: '마법기사과 담임'),
  ],
  typingSpeedMultiplier: 1.3,
  affectionStages: [
    AffectionStage(minScore: 0, maxScore: 19, stageLabel: '비밀 친구'),
    AffectionStage(minScore: 20, maxScore: 39, stageLabel: '가면 너머'),
    AffectionStage(minScore: 40, maxScore: 59, stageLabel: '소문'),
    AffectionStage(minScore: 60, maxScore: 79, stageLabel: '고백 직전'),
    AffectionStage(minScore: 80, maxScore: 100, stageLabel: '기사의 맹세'),
  ],
);

/// 회사별 '한글 한 글자 = 몇 토큰' 어림값과 그 밖의 글자(영문·숫자·JSON 기호) 몇 자 = 1토큰
const hangulTokens = {AiProvider.claude: 1.3, AiProvider.openai: 0.9, AiProvider.gemini: 0.8};
const otherCharsPerToken = 3.5;

/// 보이지 않는 '생각' 토큰도 출력으로 청구됨. 대본 쓰기(보통 깊이)는 보이는 출력의 0.5배, 자유대화(얕게)는 한 번에 80토큰으로 어림
const scriptThinkingRatio = 0.5;
const chatThinkingTokens = 80;
const wonPerUsd = 1400;

int tokens(String text, AiProvider p) {
  var hangul = 0, other = 0;
  for (final r in text.runes) {
    if (r >= 0xAC00 && r <= 0xD7A3) {
      hangul++;
    } else if (r > 32) {
      other++;
    }
  }
  return (hangul * hangulTokens[p]! + other / otherCharsPerToken).round();
}

/// 예시 캐릭터 이벤트를 AI 대본 응답 모양(scenes)으로 바꿈 → 실제 대본과 비슷한 길이의 가짜 응답
Map<String, dynamic> asScript(ScenarioBundle b, ScenarioEventModel e) {
  final nodes = b.nodes.values.where((n) => n.eventId == e.id).toList()
    ..sort((x, y) => x.stepOrder.compareTo(y.stepOrder));
  return {
    'scenes': [
      for (final n in nodes)
        {
          'scene': n.id,
          'step': n.stepOrder,
          'lines': [
            for (final l in n.characterBubbles) {'text': l.text, 'speed': l.speedFactor, 'photo': l.photoLabel ?? ''},
          ],
          'choices': [
            for (final c in n.choices)
              {
                'label': c.buttonLabel,
                'user_messages': [for (final u in c.userBubbles) u.text],
                'affection': c.affectionDelta,
                'next_scene': c.nextNodeId ?? '',
              },
          ],
        },
    ],
    'cutscene_step': e.cutsceneTriggerStep ?? 0,
  };
}

/// 좋은 선택만 골랐을 때 이 대화 하나를 보는 데 걸리는 시간(초). 채팅방의 타자 속도 규칙과 같음 + 선택지 고르는 시간
double playSeconds(ScenarioBundle b, ScenarioEventModel e, {required double pace, double thinkPerChoice = 6}) {
  var ms = e.timeNotice != null ? 900.0 : 0.0;
  var node = b.firstNodeOf(e.id);
  var guard = 0;
  while (node != null && guard++ < 30) {
    for (final bubble in node.characterBubbles) {
      final chars = bubble.text.runes.length;
      final typing = ((700 + chars * 150) * bubble.speedFactor * pace).clamp(450 * pace, 9000 * pace);
      ms += 500 * pace + typing;
      if (bubble.speedFactor >= 1.3 && typing > 1500 * pace) ms += 900 * pace;
    }
    if (node.choices.isEmpty) break;
    final best = node.choices.reduce((a, c) => c.affectionDelta > a.affectionDelta ? c : a);
    ms += thinkPerChoice * 1000 + 380 * (best.userBubbles.length - 1) + 700;
    node = best.nextNodeId != null ? b.nodes[best.nextNodeId] : null;
  }
  return ms / 1000 + 1.2;
}

String kindOf(ScenarioEventModel e) => switch (e.eventType) {
      ScenarioEventType.daily => 'daily',
      ScenarioEventType.special => 'special',
      ScenarioEventType.ending => 'ending',
      _ => 'event',
    };

class Recorder implements HttpClientAdapter {
  Recorder(this.samples);

  final Map<String, List<(ScenarioBundle, ScenarioEventModel)>> samples;
  final requests = <String>[];
  final responses = <String>[];
  final kinds = <String>[];
  final _used = <String, int>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final raw = utf8.decode(await requestStream!.expand((c) => c).toList());
    final body = jsonDecode(raw) as Map<String, dynamic>;
    // 요청에서 실제로 모델이 읽는 부분: system + user + JSON 모양
    requests.add('${body['system']}\n${body['messages'][0]['content']}\n${jsonEncode(body['output_config']['format']['schema'])}');
    final user = body['messages'][0]['content'] as String;
    final Map<String, dynamic> answer;
    if (user.contains('이야기 목차(talks)')) {
      kinds.add('목차');
      answer = outline();
    } else {
      final kind = user.contains('종류: 일상')
          ? 'daily'
          : user.contains('종류: 특별')
              ? 'special'
              : user.contains('종류: 엔딩')
                  ? 'ending'
                  : 'event';
      kinds.add(kind);
      final list = samples[kind]!;
      final i = _used.update(kind, (v) => v + 1, ifAbsent: () => 0);
      final (b, e) = list[i % list.length];
      answer = asScript(b, e);
    }
    final text = jsonEncode(answer);
    responses.add(text);
    return ResponseBody.fromString(
      jsonEncode({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': text},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  /// 50개 대화 목차 (제목·줄거리는 실제 AI 목차와 비슷한 길이로)
  Map<String, dynamic> outline() {
    final talks = <Map<String, dynamic>>[];
    for (final s in prince.affectionStages) {
      for (var i = 0; i < 9; i++) {
        final event = i.isEven && i < 8;
        talks.add({
          'kind': event ? 'event' : 'daily',
          'stage': s.stageLabel,
          'title': event ? '건국제 무도회에서 사라진 황자님' : '통신구슬로 듣는 오늘의 회의 뒷담화',
          'time_notice': '며칠 뒤 저녁',
          'synopsis': '카이엔이 무도회 도중 사라져 발코니에서 혼자 있는 걸 {이름}이 찾아낸다. 가면을 벗은 그가 형 이야기를 처음으로 꺼낸다.',
          'cutscene': event && i < 4 ? '달빛 아래 발코니에서 장갑을 벗어 건네는 카이엔' : '',
          'from_hour': 0,
          'to_hour': 0,
        });
      }
    }
    for (var i = 0; i < 4; i++) {
      talks.insert(8 + i * 10, {
        'kind': 'special', 'stage': '비밀 친구', 'title': '잠 안 오는 새벽의 통신',
        'time_notice': '', 'synopsis': '새벽에 통신구슬이 울린다. 카이엔이 잠이 안 온다며 아무 말이나 해 달라고 한다.',
        'cutscene': '', 'from_hour': 23, 'to_hour': 1,
      });
    }
    talks.add({
      'kind': 'ending', 'stage': '기사의 맹세', 'title': '졸업식 날의 맹세', 'time_notice': '졸업식 날',
      'synopsis': '황위 대신 {이름}을 고르겠다고 카이엔이 무릎을 꿇는다.', 'cutscene': '', 'from_hour': 0, 'to_hour': 0,
    });
    return {
      'tagline': prince.tagline, 'tags': prince.tags, 'world_setting': prince.worldSetting, 'quote': prince.quote,
      'profile_fields': [for (final f in prince.profileFields) {'label': f.label, 'value': f.value}],
      'traits': [
        {'left': '무심함', 'right': '다정함', 'percent': 70},
        {'left': '진지함', 'right': '장난기', 'percent': 80},
        {'left': '숨김', 'right': '솔직함', 'percent': 30},
      ],
      'sample_quotes': [
        {'situation': '무도회 뒤', 'body': '오늘 나 웃는 거 봤어? 연습한 거야. 너한테는 안 그런다.'},
        {'situation': '회의 끝나고', 'body': '회의 끝났어. 아니, 너 보려고 일부러 일찍 끝낸 거 아닌데.'},
        {'situation': '화났을 때', 'body': '{이름}, 지금 그 말 다시 해 보실래요?'},
      ],
      'talks': talks,
    };
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('50개 대화 캐릭터: AI 생성 사용량·금액과 예상 플레이 시간', () async {
    ScenarioBundle load(String path) =>
        ScenarioBundle.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
    final bundles = [load('assets/scenarios/sample_character.json'), load('assets/scenarios/example_seo_ijun.json')];

    final samples = <String, List<(ScenarioBundle, ScenarioEventModel)>>{};
    for (final b in bundles) {
      for (final e in b.events) {
        samples.putIfAbsent(kindOf(e), () => []).add((b, e));
      }
    }

    final recorder = Recorder(samples);
    final client = ClaudeStudioClient(dio: Dio()..httpClientAdapter = recorder);
    final brief = const StudioBrief(character: prince, eventsPerStage: 4, dailiesPerStage: 5, specials: 4);
    final bundle = await client.generate(apiKey: 'test', model: 'claude-opus-5-5', brief: brief);

    final out = StringBuffer();
    void line([String s = '']) => out.writeln(s);

    final byKind = <String, int>{};
    for (final e in bundle.events) {
      byKind.update(kindOf(e), (v) => v + 1, ifAbsent: () => 1);
    }
    line('대화 ${bundle.events.length}개: 호감도 이벤트 ${byKind['event']}, 일상 ${byKind['daily']}, '
        '특별 ${byKind['special']}, 엔딩 ${byKind['ending']} · API 호출 ${recorder.requests.length}번');
    line();

    // 1) 플레이 시간: 예시 캐릭터 대화를 종류별로 평균 내서 50개 구성에 곱함
    for (final tempo in [1.0, 0.6]) {
      final pace = prince.typingSpeedMultiplier * tempo;
      double avg(String kind) {
        final list = samples[kind]!;
        return list.map((s) => playSeconds(s.$1, s.$2, pace: pace)).reduce((a, b) => a + b) / list.length;
      }

      final total = byKind.entries.map((k) => avg(k.key) * k.value).reduce((a, b) => a + b);
      line('플레이(대화 속도 x$tempo, 타자 스타일 느긋하게 1.3): 이벤트 평균 ${avg('event').round()}초, '
          '일상 ${avg('daily').round()}초, 특별 ${avg('special').round()}초 → 합계 ${(total / 60).round()}분');
    }
    line();

    // 2) AI로 만들기 사용량
    final inputChars = recorder.requests.map((r) => r.length).reduce((a, b) => a + b);
    final outputChars = recorder.responses.map((r) => r.length).reduce((a, b) => a + b);
    line('요청 글자 ${inputChars ~/ 1000}천 자, 응답 글자 ${outputChars ~/ 1000}천 자');
    line();
    line('| 모델 | 입력 토큰 | 출력 토큰(생각 포함) | AI로 만들기 1번 | 자유대화 1턴 |');
    line('| --- | --- | --- | --- | --- |');

    // 자유대화 1턴: 앱의 진짜 자유대화 요청(캐릭터 설정 + 최근 30말풍선)을 만들어 잼
    final chatOut = jsonEncode({'replies': ['나 지금 3층 창가', '너 오면 홍차 남겨 둘게'], 'affection_delta': 1});
    final chatRecorder = _ChatRecorder(chatOut);
    await ClaudeChatClient(dio: Dio()..httpClientAdapter = chatRecorder).reply(
      apiKey: 'test',
      model: 'claude-opus-5-5',
      character: bundle.character,
      stageLabel: '가면 너머',
      currentEventTitle: '건국제 무도회에서 사라진 황자님',
      userName: '말랑',
      history: [
        for (var i = 0; i < 30; i++)
          ChatMessageLog(
            id: '$i', isUser: i.isOdd, speakerCharacterId: 'c', speakerName: '',
            text: i.isOdd ? '오늘 회의는 어땠어?' : '회의 끝났어. 아니, 너 보려고 일찍 끝낸 거 아닌데', timestamp: DateTime(2026),
          ),
      ],
      newUserMessages: ['지금 도서관이야?', '나도 갈까'],
    );
    final chatRequest = chatRecorder.request!;

    for (final p in AiProvider.values) {
      for (final m in p.models) {
        final inTok = recorder.requests.map((r) => tokens(r, p)).reduce((a, b) => a + b);
        final visibleOut = recorder.responses.map((r) => tokens(r, p)).reduce((a, b) => a + b);
        final outTok = (visibleOut * (1 + scriptThinkingRatio)).round();
        final usd = inTok / 1e6 * m.inputUsdPerMTok + outTok / 1e6 * m.outputUsdPerMTok;
        final chatIn = tokens(chatRequest, p);
        final chatOutTok = tokens(chatOut, p) + chatThinkingTokens;
        final chatUsd = chatIn / 1e6 * m.inputUsdPerMTok + chatOutTok / 1e6 * m.outputUsdPerMTok;
        line('| ${m.label} | ${(inTok / 1000).toStringAsFixed(0)}천 | ${(outTok / 1000).toStringAsFixed(0)}천 | '
            '약 ${(usd * wonPerUsd).round()}원 (\$${usd.toStringAsFixed(2)}) | 약 ${(chatUsd * wonPerUsd).toStringAsFixed(1)}원 |');
      }
    }
    // ignore: avoid_print
    print(out);
    Directory('build').createSync();
    File('build/usage_report.md').writeAsStringSync(out.toString());
    expect(bundle.events.length, 50);
  });
}

class _ChatRecorder implements HttpClientAdapter {
  _ChatRecorder(this.answer);

  final String answer;
  String? request;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = jsonDecode(utf8.decode(await requestStream!.expand((c) => c).toList())) as Map<String, dynamic>;
    request = '${body['system']}\n${body['messages'][0]['content']}\n${jsonEncode(body['output_config']['format']['schema'])}';
    return ResponseBody.fromString(
      jsonEncode({
        'content': [
          {'type': 'text', 'text': answer},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
