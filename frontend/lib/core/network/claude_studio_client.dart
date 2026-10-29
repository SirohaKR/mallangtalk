import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';
import 'claude_chat_client.dart';

/// 만들기 화면에서 적은 캐릭터 설정 + 만들 분량 (AI 생성의 재료)
class StudioBrief {
  /// 만들기 화면의 캐릭터 (이름·캐릭터 설정·세계관·유저 설정·주변 인물·비밀·호감도 단계·타자 스타일)
  final CharacterModel character;
  final int eventsPerStage;
  final int dailiesPerStage;
  /// 실제 시간에만 오는 특별 이벤트 수
  final int specials;

  const StudioBrief({
    required this.character,
    this.eventsPerStage = 2,
    this.dailiesPerStage = 3,
    this.specials = 1,
  });

  List<AffectionStage> get stages => character.affectionStages;

  /// 만들어질 대화 수 (호감도 이벤트 + 일상 대화 + 특별 이벤트 + 엔딩)
  int get totalTalks => stages.length * (eventsPerStage + dailiesPerStage) + specials + 1;
}

/// 생성 진행 상황 (화면의 진행 막대용)
typedef StudioProgress = void Function(String message, int done, int total);

final claudeStudioClientProvider = Provider<ClaudeStudioClient>((ref) => ClaudeStudioClient());

/// [초보자 노트] 만들기 화면의 캐릭터 설정을 토대로 Claude가 호감도 단계별 이벤트·일상 대화·특별 이벤트·엔딩과
/// 모든 대사를 만들어 주는 클라이언트입니다.
/// 1. 목차 만들기: 단계마다 이벤트 몇 개, 일상 대화 몇 개, 실제 시간 특별 이벤트, 마지막에 엔딩 (한 번 호출)
///    비어 있는 캐릭터 정보(한줄 소개·태그·세계관·캐릭터 정보 항목 등)도 이때 채움
/// 2. 대사 쓰기: 대화 하나마다 장면·말풍선·선택지 (대화 수만큼 호출, 3개씩 동시에). 이벤트 하나만 따로 쓸 수도 있음
/// 3. 균형 맞추기: 좋은 선택을 하면 끝까지 갈 수 있게 호감도 점수를 자동 보정
/// 말랑톡 서버에서 열었으면 [relay]로 서버의 .env 키를 쓰고, 아니면 설정 화면의 내 키(BYOK)를 씁니다.
class ClaudeStudioClient {
  ClaudeStudioClient({Dio? dio})
      : _dio = dio ??
            Dio(aiDioOptions(total: const Duration(minutes: 6), web: kIsWeb));

  final Dio _dio;

  /// 부를 때마다 쓴 토큰 수를 알려 줌 (사용량·금액 측정용)
  void Function(AiUsage usage)? onUsage;

  Future<ScenarioBundle> generate({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required StudioBrief brief,
    StudioProgress? onProgress,
  }) async {
    final total = brief.totalTalks + 1;
    onProgress?.call('이야기 목차를 짜는 중', 0, total);

    final (outline, character) = await _outline(provider: provider, apiKey: apiKey, relay: relay, model: model, brief: brief);
    final characterId = character.id;
    onProgress?.call('대사를 쓰는 중', 1, total);

    final events = <ScenarioEventModel>[];
    for (var i = 0; i < outline.length; i++) {
      final o = outline[i];
      final kind = o['kind'] as String;
      final type = switch (kind) {
        'daily' => ScenarioEventType.daily,
        'ending' => ScenarioEventType.ending,
        'special' => ScenarioEventType.special,
        _ => ScenarioEventType.autoStory,
      };
      final cutscene = (o['cutscene'] as String? ?? '').trim();
      final stage = brief.stages.where((s) => s.stageLabel == o['stage']).firstOrNull ??
          brief.stages.last;
      final from = (o['from_hour'] as num? ?? 22).toInt().clamp(0, 23);
      final to = (o['to_hour'] as num? ?? 2).toInt().clamp(0, 24);
      events.add(ScenarioEventModel(
        id: 'evt_${i + 1}',
        characterId: characterId,
        chapterOrder: type == ScenarioEventType.ending ? 999 : (i + 1) * 10,
        eventType: type,
        title: (o['title'] as String).trim(),
        timeNotice: type == ScenarioEventType.special
            ? null
            : (o['time_notice'] as String?)?.trim(),
        stageLabel: stage.stageLabel,
        synopsis: [
          (o['synopsis'] as String? ?? '').trim(),
          if ((o['speech'] as String? ?? '').trim().isNotEmpty) '말투: ${(o['speech'] as String).trim()}',
        ].where((t) => t.isNotEmpty).join('\n'),
        realTime: type == ScenarioEventType.special
            ? RealTimeWindow(fromHour: from, toHour: from == to ? (from + 3) % 24 : to)
            : null,
        cutscenePhotoTitle: type == ScenarioEventType.autoStory && cutscene.isNotEmpty ? cutscene : null,
        participantCharacterIds: [characterId],
      ));
    }

    final nodes = <String, ScriptNodeModel>{};
    final finalEvents = <ScenarioEventModel>[];
    final writtenLines = <String>[];
    var done = 1;
    // 너무 많이 동시에 부르면 요청 한도에 걸리니 3개씩.
    // Gemini 무료 등급은 분당 요청·토큰 한도가 작아서 하나씩 차례로 부름
    final parallel = provider == AiProvider.gemini ? 1 : 3;
    for (var start = 0; start < events.length; start += parallel) {
      final batch = events.sublist(start, (start + parallel).clamp(0, events.length));
      final results = await Future.wait([
        for (final event in batch)
          writeScript(
            provider: provider, apiKey: apiKey, relay: relay, model: model,
            character: character, event: event, outline: events, previousLines: writtenLines,
          ),
      ]);
      for (var j = 0; j < batch.length; j++) {
        final (eventNodes, cutsceneStep) = results[j];
        nodes.addAll({for (final n in eventNodes) n.id: n});
        writtenLines.addAll([
          for (final n in eventNodes)
            for (final b in n.characterBubbles)
              if (b.text.isNotEmpty) b.text,
        ]);
        final e = batch[j];
        finalEvents.add(e.withCutsceneStep(e.cutscenePhotoTitle != null ? cutsceneStep : null));
        done++;
        onProgress?.call('대사를 쓰는 중 · ${e.title}', done, total);
      }
    }

    finalEvents.sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    return balanceScenario(ScenarioBundle(character: character, events: finalEvents, nodes: nodes));
  }

  String _characterSheet(CharacterModel c) => '''
[캐릭터]
이름: ${c.name}
상태메시지: ${c.statusMessage}
${c.aiCharacterSheet}${c.lorebook.isEmpty ? '' : '\n\n[로어북] (키워드: 내용)\n${c.lorebook.where((e) => e.content.trim().isNotEmpty).map((e) => '- ${e.keys.join(', ')}: ${e.content.trim()}').join('\n')}'}

[호감도 단계] (낮은 단계부터)
${c.affectionStages.map((s) => '- ${s.stageLabel} (${s.minScore}~${s.maxScore}점)').join('\n')}''';

  static const _system = '''
너는 메신저 연애 시뮬레이션 게임 "말랑톡"의 시나리오 작가다. 유저는 카톡으로 캐릭터와 대화하며 호감도를 쌓는다.
- 대사는 실제 카톡처럼 짧게 끊어 친다. 괄호 지문, 행동 묘사, 나레이션은 쓰지 않는다. 이모지는 거의 안 쓴다.
- 캐릭터의 말투·습관·취미가 대사마다 살아 있어야 한다. 단계보다 앞서 나가는 고백이나 스킨십은 쓰지 않는다.
- 유저는 평소 "너"라고 부르고, 이름을 부를 때만 {{user}} 라고 쓴다(앱이 플레이어 별명으로 바꿔 넣는다). 유저 성별은 정하지 않는다.
- 플레이어가 언제 접속할지 모르므로 대사에 "지금 밤 11시" 같은 정확한 시각을 쓰지 않는다.
- 이 게임은 톡이다. 모든 대화는 캐릭터와 유저가 떨어져서 메신저로 주고받는 톡이다. 만나자고 약속을 잡거나, 만나고 헤어진 뒤 그 일을 톡으로 돌아보는 건 되지만, 같은 자리에서 얼굴을 보며 하는 대화("왔네", "가만있어 봐", "나 쳐다보지 마")는 쓰지 않는다.
- 마음을 정식으로 고백하는 건 엔딩에서만 한다. 그 전에는 돌려 말하거나 예고하는 데서 멈춘다.
- 유저 말투(반말·존댓말)는 처음 정한 대로 끝까지 지킨다. 바뀐다면 바뀌는 계기가 되는 대화가 있어야 하고, 그 뒤로는 바뀐 말투를 지킨다.
- 세계관에 없는 물건·단어는 쓰지 않는다. 예를 들어 판타지 세계면 폰·카톡 대신 그 세계의 연락 수단을 쓴다.
- 사진(앨범 장면·사진 말풍선)은 캐릭터가 톡에 올리는 사진이다: 셀카, 누가 찍어 준 캐릭터 사진, 물건·음식·풍경 사진. 캐릭터 혼자, 캐릭터와 주변 인물(설정에 있는 인물)이 함께, 또는 사람 없이 나온다. 주변 인물이 나오면 그 인물의 외모(머리색·눈색·옷차림 등)를 묘사에 꼭 적는다. 손만 나오는 사진과 유저가 나오는 사진은 쓰지 않는다.''';

  /// 목차 + 비어 있는 캐릭터 정보(한줄 소개·태그·세계관·캐릭터 정보 항목·대표 대사·성격 막대·대사 예시)를 한 번에 만듦
  Future<(List<Map<String, dynamic>>, CharacterModel)> _outline({
    required AiProvider provider,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required StudioBrief brief,
  }) async {
    final base = brief.character;
    final stageNames = [for (final s in brief.stages) s.stageLabel];
    final schema = {
      'type': 'object',
      'properties': {
        'tagline': {'type': 'string', 'description': '캐릭터 갤러리에 보일 한줄 소개 (30자 이내, 궁금해지게)'},
        'tags': {'type': 'array', 'items': {'type': 'string'}, 'description': '캐릭터 태그 3~5개, # 없이'},
        'world_setting': {'type': 'string', 'description': '세계관 설정 요약 2~3문장 (배경이 되는 곳·시대·분위기)'},
        'quote': {'type': 'string', 'description': '캐릭터를 한 번에 보여주는 대표 대사 한 줄'},
        'profile_fields': {
          'type': 'array',
          'description': '캐릭터 정보 항목 4~6개. 예: 나이, 직업, 생일, 좋아하는 것, 싫어하는 것',
          'items': {
            'type': 'object',
            'properties': {'label': {'type': 'string'}, 'value': {'type': 'string'}},
            'required': ['label', 'value'],
            'additionalProperties': false,
          },
        },
        'traits': {
          'type': 'array',
          'description': '성격 막대 3~4개. left↔right 양쪽 성향과 right 쪽으로 기운 정도(0~100)',
          'items': {
            'type': 'object',
            'properties': {
              'left': {'type': 'string'},
              'right': {'type': 'string'},
              'percent': {'type': 'integer'},
            },
            'required': ['left', 'right', 'percent'],
            'additionalProperties': false,
          },
        },
        'sample_quotes': {
          'type': 'array',
          'description': '상황별 대사 예시 3개 (말투가 드러나게)',
          'items': {
            'type': 'object',
            'properties': {'situation': {'type': 'string'}, 'body': {'type': 'string'}},
            'required': ['situation', 'body'],
            'additionalProperties': false,
          },
        },
        'talks': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'kind': {'type': 'string', 'enum': ['event', 'daily', 'special', 'ending']},
              'stage': {'type': 'string', 'enum': stageNames},
              'title': {'type': 'string'},
              'time_notice': {
                'type': 'string',
                'description': '대화 시작 전 가운데 뜨는 장면 전환 문구. 앞 대화 기준 상대적인 말만: 다음 날, 그날 밤, 며칠 뒤 저녁, 주말 오후. 요일·시각 숫자 금지',
              },
              'synopsis': {'type': 'string', 'description': '이 대화(톡)에서 일어나는 일 2~3문장. 만남은 약속 잡기나 만나고 와서 돌아보는 톡으로'},
              'speech': {
                'type': 'string',
                'description': '이 대화에서 유저와 캐릭터가 서로 쓰는 말투. 예: 둘 다 반말 / 유저는 존댓말, 캐릭터는 반말. 이 대화에서 바뀌면 바뀌는 계기와 함께: 유저 존댓말→반말 (캐릭터가 말 놓자고 해서)',
              },
              'cutscene': {
                'type': 'string',
                'description': 'event만: 앨범에 모이는 사진 한 줄 묘사. 캐릭터가 톡에 올리는 셀카·누가 찍어 준 캐릭터 사진·물건이나 풍경 사진. 캐릭터 혼자, 주변 인물과 함께(그 인물의 외모도 적기), 또는 사람 없이. 손만·유저는 X. 없으면 빈 문자열',
              },
              'from_hour': {'type': 'integer', 'description': 'special만: 열리는 실제 시각 시작(0~23). 나머지는 0'},
              'to_hour': {'type': 'integer', 'description': 'special만: 끝 시각(0~24, 자정을 넘기면 시작보다 작게). 나머지는 0'},
            },
            'required': ['kind', 'stage', 'title', 'time_notice', 'synopsis', 'speech', 'cutscene', 'from_hour', 'to_hour'],
            'additionalProperties': false,
          },
        },
      },
      'required': [
        'tagline', 'tags', 'world_setting', 'quote', 'profile_fields', 'traits', 'sample_quotes', 'talks',
      ],
      'additionalProperties': false,
    };

    final user = '''
${_characterSheet(base)}

먼저 캐릭터 정보(tagline, tags, world_setting, quote, profile_fields, traits, sample_quotes)를 설정에 맞게 채우고,
이 캐릭터의 이야기 목차(talks)를 짜 줘. 목차는 시간 순서대로 나열한다.
- 각 호감도 단계마다 호감도 이벤트(kind=event) ${brief.eventsPerStage}개와 일상 대화(kind=daily) ${brief.dailiesPerStage}개.
  이벤트는 관계가 한 발짝 나아가는 사건, 일상 대화는 취미·하루 얘기처럼 가벼운 잡담이다.
- 특별 이벤트(kind=special) ${brief.specials}개: 플레이어가 실제로 그 시각에 대화방에 있을 때만 한 번 오는 톡이다.
  늦은 밤 안부, 새벽 감성 톡처럼 시간대가 중요한 내용으로 쓰고 from_hour~to_hour에 그 시간대를 적는다. 목차의 아무 곳에나 둬도 된다.
- 이벤트 중 절반 정도에는 cutscene(앨범 사진)을 넣는다. 셀카, 누가 찍어 준 캐릭터 사진, 주변 인물과 함께 찍은 사진(그 인물의 외모도 적기), 물건·풍경 사진 중에서 고르고 손만·유저가 나오는 사진은 쓰지 않는다. 일상 대화·특별 이벤트의 cutscene은 빈 문자열.
- 모든 대화는 톡이다. 만나는 일은 대화와 대화 사이에 일어나고, 줄거리는 만날 약속을 잡는 톡이나 만나고 와서 돌아보는 톡으로 쓴다.
- 말투(speech): 첫 대화의 말투는 유저 설정·관계에 맞게 정하고 다음 대화들도 같은 말투를 이어 간다. 존댓말에서 반말로(또는 반대로) 바뀌는 건 관계가 가까워지는 자연스러운 계기가 있는 대화 한 곳에서만 하고, 그 대화의 speech와 synopsis에 계기를 적는다. 그 뒤 대화는 바뀐 말투를 쓴다.
- 고백은 엔딩에서만 한다. 엔딩 전 대화에서는 고백을 예고하거나 암시하는 데서 멈추고, 같은 사건(고백·약속·발표)을 두 번 일어나게 쓰지 않는다.
- 맨 마지막에 마지막 단계의 엔딩(kind=ending) 1개. 엔딩은 관계가 결실을 맺는 톡이다.
- 같은 단계 안에서는 이벤트와 일상 대화를 번갈아 배치한다.''';

    // 목차 한 줄(제목·줄거리·컷씬)에 한글 토큰이 꽤 들고, Claude는 보이지 않는 생각도 같은 한도에서 써서 대화 수에 맞춰 늘림
    final talkCount = brief.stages.length * (brief.eventsPerStage + brief.dailiesPerStage) + brief.specials + 1;
    final json = await _call(
      provider: provider, apiKey: apiKey, relay: relay, model: model, user: user, schema: schema,
      maxTokens: (8000 + talkCount * 500).clamp(9000, 64000),
    );
    final talks = [for (final t in json['talks'] as List? ?? const []) t as Map<String, dynamic>];
    if (talks.where((t) => t['kind'] == 'event').isEmpty) {
      throw const ClaudeChatException('AI가 이벤트 목차를 만들지 못했어요. 다시 시도해 주세요.');
    }
    // 엔딩이 없거나 여러 개면 정리
    final endings = talks.where((t) => t['kind'] == 'ending').toList();
    talks.removeWhere((t) => t['kind'] == 'ending');
    if (endings.isNotEmpty) talks.add(endings.first);

    String text(String key) => (json[key] as String? ?? '').trim();
    final tags = [
      for (final t in json['tags'] as List? ?? const [])
        if ((t as String).trim().isNotEmpty) t.replaceAll('#', '').trim(),
    ].take(5).toList();
    // 제작자가 이미 적은 칸은 그대로 두고 빈칸만 AI 것으로 채움
    final character = CharacterModel(
      id: base.id.isEmpty || base.id == 'draft' ? 'char_${DateTime.now().millisecondsSinceEpoch}' : base.id,
      creatorId: base.creatorId,
      name: base.name.trim(),
      statusMessage: base.statusMessage.trim(),
      avatarUrl: base.avatarUrl,
      tagline: base.tagline.trim().isNotEmpty ? base.tagline : text('tagline'),
      tags: base.tags.isNotEmpty ? base.tags : tags,
      worldviewPrompt: base.worldviewPrompt,
      worldSetting: base.worldSetting.trim().isNotEmpty ? base.worldSetting : text('world_setting'),
      quote: base.quote.trim().isNotEmpty ? base.quote : text('quote'),
      profileFields: base.profileFields.isNotEmpty
          ? base.profileFields
          : [
              for (final f in json['profile_fields'] as List? ?? const [])
                ProfileField.fromJson(f as Map<String, dynamic>),
            ].where((f) => f.label.isNotEmpty && f.value.isNotEmpty).toList(),
      traits: base.traits.isNotEmpty
          ? base.traits
          : [
              for (final t in json['traits'] as List? ?? const [])
                PersonalityTrait.fromJson(t as Map<String, dynamic>),
            ].where((t) => t.left.isNotEmpty).toList(),
      sampleQuotes: base.sampleQuotes.isNotEmpty
          ? base.sampleQuotes
          : [
              for (final q in json['sample_quotes'] as List? ?? const [])
                CharacterQuote.fromJson(q as Map<String, dynamic>),
            ].where((q) => q.body.isNotEmpty).toList(),
      secret: base.secret,
      userRole: base.userRole,
      extraCast: base.extraCast,
      lorebook: base.lorebook,
      themeColor: base.themeColor,
      gender: base.gender,
      unlisted: base.unlisted,
      chatBackground: base.chatBackground,
      chatBackgroundImage: base.chatBackgroundImage,
      bubbleStyle: base.bubbleStyle,
      typingSpeedMultiplier: base.typingSpeedMultiplier,
      affectionStages: base.affectionStages,
    );
    return (talks, character);
  }

  /// 만들기 단계의 '빈 칸 AI로 채우기': 캐릭터 설정을 보고 [fields]에 든 칸만 써서 돌려줌 (화면이 빈 칸에만 넣음)
  /// fields: profile_fields, quote, sample_quotes, traits, world_setting, user_role, extra_cast, secret, lorebook
  Future<Map<String, dynamic>> fillBlanks({
    required AiProvider provider,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required List<String> fields,
  }) async {
    Map<String, dynamic> pairs(String a, String b, String description) => {
          'type': 'array',
          'description': description,
          'items': {
            'type': 'object',
            'properties': {a: {'type': 'string'}, b: {'type': 'string'}},
            'required': [a, b],
            'additionalProperties': false,
          },
        };
    final all = <String, Map<String, dynamic>>{
      'profile_fields': pairs('label', 'value', '캐릭터 정보 항목 5~7개. 예: 나이, 직업, 생일, 외모, 좋아하는 것, 싫어하는 것'),
      'quote': {'type': 'string', 'description': '캐릭터를 한 번에 보여 주는 대표 대사 한 줄'},
      'sample_quotes': pairs('situation', 'body', '상황별 대사 예시 3개 (말투가 드러나게)'),
      'traits': {
        'type': 'array',
        'description': '성격 막대 3~4개. left↔right 양쪽 성향과 right 쪽으로 기운 정도(0~100)',
        'items': {
          'type': 'object',
          'properties': {'left': {'type': 'string'}, 'right': {'type': 'string'}, 'percent': {'type': 'integer'}},
          'required': ['left', 'right', 'percent'],
          'additionalProperties': false,
        },
      },
      'world_setting': {'type': 'string', 'description': '세계관 설정 2~3문장 (배경이 되는 곳·시대·분위기)'},
      'user_role': {'type': 'string', 'description': '이 이야기에서 유저가 누구인지 1~2문장. 유저 이름 자리는 {{user}}'},
      'extra_cast': pairs('name', 'role', '대화에 이름이 나올 주변 인물 2~3명 (친구·가족·반려동물). role은 캐릭터와의 관계와 한 줄 특징'),
      'secret': {'type': 'string', 'description': '유저는 아직 모르고 이야기가 서서히 드러낼 캐릭터의 비밀 1~2문장. 유저 이름 자리는 {{user}}'},
      'lorebook': pairs('keys', 'content',
          '로어북 항목 5~8개: 대화에 그 말이 나오면 캐릭터가 떠올릴 구체적인 사실 (장소·물건·추억·주변 인물·반려동물·습관 등). keys는 대화에 나올 만한 낱말 1~3개를 쉼표로, content는 1~2문장. 설정에 이미 있는 사실을 구체적으로 늘리고 어긋나지 않게'),
    };
    final wanted = [for (final f in fields) if (all.containsKey(f)) f];
    if (wanted.isEmpty) return const {};
    final schema = {
      'type': 'object',
      'properties': {for (final f in wanted) f: all[f]},
      'required': wanted,
      'additionalProperties': false,
    };
    final user = '''
${_characterSheet(character)}

위 캐릭터 설정에 어울리게 아래 칸을 채워 줘. 설정에 이미 있는 사실과 어긋나지 않게 쓴다.
채울 칸: ${wanted.join(', ')}''';
    return _call(provider: provider, apiKey: apiKey, relay: relay, model: model, user: user, schema: schema, maxTokens: 4000);
  }

  /// 대화 하나의 대사(장면·말풍선·선택지)를 씀. 돌려주는 값: (대사 노드, 컷씬이 뜨는 단계)
  /// outline은 앞뒤 흐름을 알려 주려고 넘기는 전체 대화 목록 (지금 쓸 대화 포함)
  Future<(List<ScriptNodeModel>, int?)> writeScript({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required ScenarioEventModel event,
    required List<ScenarioEventModel> outline,
    List<String> previousLines = const [],
  }) async {
    final schema = {
      'type': 'object',
      'properties': {
        'scenes': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'scene': {'type': 'string', 'description': '장면 이름. 예: 1, 2, 3-수락, 3-거절'},
              'user_first': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': '선톡: 이 장면에서 캐릭터보다 유저가 먼저 보내는 톡. 보통 빈 배열',
              },
              'step': {'type': 'integer', 'description': '몇 번째 단계인지 (1부터)'},
              'lines': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'text': {'type': 'string'},
                    'speed': {'type': 'number', 'description': '0.5 툭 빠르게 ~ 1.5 망설이며 느리게'},
                    'photo': {
                      'type': 'string',
                      'description': '사진을 보내는 말풍선이면 사진 묘사(셀카·누가 찍어 준 캐릭터 사진·주변 인물과 함께 찍은 사진(그 인물 외모도)·물건이나 풍경, 캐릭터가 실제로 찍어 보낼 수 있는 것), 아니면 빈 문자열',
                    },
                    'late': {'type': 'boolean', 'description': '바빠서·망설여서 답장이 늦게 오는 말풍선이면 true (보통 false)'},
                  },
                  'required': ['text', 'speed', 'photo', 'late'],
                  'additionalProperties': false,
                },
              },
              'choices': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'label': {'type': 'string', 'description': '선택지 버튼 요약. 예: 같이 가자고 하기'},
                    'user_messages': {
                      'type': 'array',
                      'items': {'type': 'string'},
                      'description': '유저가 실제로 보내는 톡. "이어서", "...", "다음" 같은 자리채움 말은 쓰지 않는다',
                    },
                    'affection': {'type': 'integer'},
                    'next_scene': {'type': 'string', 'description': '이어질 장면 이름. 이 선택으로 대화가 끝나면 빈 문자열'},
                  },
                  'required': ['label', 'user_messages', 'affection', 'next_scene'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['scene', 'user_first', 'step', 'lines', 'choices'],
            'additionalProperties': false,
          },
        },
        'cutscene_step': {'type': 'integer', 'description': '앨범 장면이 뜨는 단계. 장면이 없으면 0'},
      },
      'required': ['scenes', 'cutscene_step'],
      'additionalProperties': false,
    };

    // [초보자 노트] 대화 분량: 호감도 이벤트·엔딩은 캐릭터 말풍선 20개쯤(쨋뀨 요청), 일상·특별은 그 절반쯤
    final (kindText, bubbleRange) = switch (event.eventType) {
      ScenarioEventType.daily => ('일상 대화 (가벼운 잡담, 장면 2~3개)', '8~12'),
      ScenarioEventType.ending => ('엔딩 (장면 4~5개, 마지막 장면은 선택지 1개 또는 없음)', '18~22'),
      ScenarioEventType.special => ('특별 이벤트 (그 시간대 분위기의 톡, 장면 2~3개)', '8~12'),
      _ => ('호감도 이벤트 (장면 4~6개, 선택에 따라 갈림길 1~2개)', '18~22'),
    };
    // 좋은 선택만 골랐을 때 이 대화에서 오를 호감도: 단계 점수 폭을 그 단계의 호감도 이벤트 수로 나눈 만큼
    final stage = character.stageNamed(event.stageLabel);
    final storyInStage = outline.where((o) => o.isAffectionEvent && o.stageLabel == event.stageLabel).length;
    final affectionBudget = event.isAffectionEvent && stage != null
        ? ((stage.maxScore - stage.minScore + 1) / (storyInStage == 0 ? 1 : storyInStage)).round().clamp(4, 30)
        : null;
    // 대화마다 연출을 조금씩 다르게 (늘 캐릭터가 먼저 말하고 선택지로 끝나면 단조로워서)
    final style = _scriptStyle(event);
    // 앞 대화의 줄거리까지 알려 줘야 이미 일어난 일(고백·약속 등)을 되풀이하지 않음
    final storySoFar = outline
        .map((o) => '- [${o.stageLabel ?? ''}] ${o.title}${o.id == event.id ? '  ← 지금 쓸 대화' : ': ${o.synopsis}'}')
        .join('\n');
    // 같은 말버릇·핑계·오타가 대화마다 반복되지 않게 앞에서 쓴 말풍선 일부를 보여 줌
    final recent = previousLines.length > 60 ? previousLines.sublist(previousLines.length - 60) : previousLines;

    final user = '''
${_characterSheet(character)}

[전체 목차]
$storySoFar

${recent.isEmpty ? '' : '[앞 대화에서 캐릭터가 이미 한 말 (같은 말버릇·핑계·농담·오타를 그대로 되풀이하지 말 것)]\n${recent.join('\n')}\n\n'}[지금 쓸 대화]
종류: $kindText
호감도 단계: ${event.stageLabel}
제목: ${event.title}
${event.isSpecial ? '실제 시간: ${event.realTime?.label ?? ''} 에 대화방에 있는 플레이어에게만 한 번 오는 특별한 톡' : '장면 전환: ${event.timeNotice ?? ''}'}
내용: ${event.synopsis}
${event.cutscenePhotoTitle != null ? '앨범 장면(CG): ${event.cutscenePhotoTitle} → 이 장면이 떠오르는 단계를 cutscene_step으로. 좋은 선택을 하면 반드시 지나가는 단계여야 한다.' : '앨범 장면 없음 → cutscene_step은 0'}

이 대화의 연출: ${style.$2}

규칙:
- ${style.$1 == _ScriptStyle.userFirst ? '첫 장면의 user_first에 유저가 먼저 보내는 톡 1~3개를 쓰고, 캐릭터는 그 톡에 답하며 시작한다. 나머지 장면의 user_first는 빈 배열' : '캐릭터가 먼저 톡을 보내며 시작한다. 모든 장면의 user_first는 빈 배열'}. 장면마다 캐릭터 말풍선 3~5개.
- ${style.$1 == _ScriptStyle.late ? '대화 중 한 번은 캐릭터가 답장을 늦게 한다: 유저의 선택 바로 다음 장면 첫 말풍선의 late를 true로 하고, 늦은 이유가 말에 묻어나게 쓴다 (예: 아 미안 씻고 왔어). 나머지 late는 false' : '모든 late는 false'}.
- 당황하거나 급하거나 들뜰 때는 일부러 오타를 내기도 한다 (예: 헐 대박ㅂ). 오타 뒤에 *고친말 로 바로잡는 말풍선을 붙이기도 한다. 대화당 0~1번, 캐릭터 말투에 맞을 때만. 앞 대화에서 쓴 오타를 똑같이 다시 쓰지 않는다.
- 말투: 내용에 적힌 '말투'를 유저 선택지(user_messages·user_first)와 캐릭터 대사 모두에서 지킨다. 적혀 있지 않으면 전체 목차와 앞 대화에서 이어지는 말투를 쓴다. 말투가 바뀌는 대화면 계기가 되는 말이 오간 뒤부터 바뀐 말투를 쓴다. 캐릭터 설정에 있는 일시적인 말투 변화(예: 화나면 존댓말)는 그대로 살린다.
- 이 대화는 톡이다. 캐릭터와 유저는 같은 자리에 있지 않다. 만났던 일은 지나간 일로 돌아보고, 만날 일은 약속으로만 쓴다.
- 사진 말풍선은 캐릭터가 직접 찍었거나 누가 찍어 준 사진만 보낸다. 주변 인물과 함께 찍은 사진이면 그 인물의 외모를 묘사에 적는다. 손만·유저가 나오는 사진은 보내지 않는다.
- 분량: 좋은 선택을 따라 끝까지 읽었을 때 캐릭터 말풍선이 모두 합쳐 $bubbleRange개가 되게 쓴다. 짧게 끊어 치는 카톡처럼, 한 말풍선은 한두 문장.
- 선택지는 2~3개. 실제로 말하는 선택지만 user_messages에 짧은 톡 1~3개를 넣는다. '이어서 듣기', '침묵하기', '답장하지 않기' 같은 행동·진행 선택지는 버튼 label에만 쓰고 user_messages는 빈 배열 []로 둔다. 버튼 설명을 실제 유저 대사로 보내지 않는다.
- affection: 캐릭터 마음에 쏙 드는 답 +2~+4, 무난한 답 +1, 서운한 답 0. 음수는 쓰지 않는다.${affectionBudget != null ? '\n- 좋은 답만 골랐을 때 이 대화에서 오르는 호감도 합이 약 $affectionBudget점이 되게 맞춘다.' : ''}
- 선택지가 없는 장면에서 대화가 끝난다. next_scene은 이 대화 안의 장면 이름만 쓴다.${style.$1 == _ScriptStyle.monologue ? '\n- 이 대화는 장면 1~2개로 짧게, 캐릭터가 혼자 연달아 말하고 유저 대답 없이(choices 빈 배열) 끝난다. 분량은 캐릭터 말풍선 5~8개.' : ''}''';

    final json = await _call(
      provider: provider,
      apiKey: apiKey, relay: relay,
      model: model,
      user: user,
      schema: schema,
      maxTokens: 24000, // 말풍선 20개 + 보이지 않는 생각까지 넉넉히
    );
    final scenes = [for (final s in json['scenes'] as List? ?? const []) s as Map<String, dynamic>];
    String nodeId(String scene) => '${event.id}_${scene.trim()}';
    final names = {for (final s in scenes) nodeId(s['scene'] as String)};
    final nodes = <ScriptNodeModel>[];
    for (final s in scenes) {
      final id = nodeId(s['scene'] as String);
      final choices = <ChoiceOption>[];
      final rawChoices = s['choices'] as List? ?? const [];
      for (var i = 0; i < rawChoices.length; i++) {
        final c = rawChoices[i] as Map<String, dynamic>;
        final next = (c['next_scene'] as String? ?? '').trim();
        final messages = [
          for (final m in c['user_messages'] as List? ?? const [])
            if ((m as String).trim().isNotEmpty) ScriptBubblePiece(text: m.trim()),
        ];
        final label = (c['label'] as String? ?? '').trim();
        choices.add(ChoiceOption(
          id: '${id}_c${i + 1}',
          buttonLabel: label.isEmpty ? (messages.firstOrNull?.text ?? '...') : label,
          userBubbles: messages,
          affectionDelta: (c['affection'] as num? ?? 0).toInt().clamp(0, 8),
          nextNodeId: next.isEmpty || !names.contains(nodeId(next)) || nodeId(next) == id
              ? null
              : nodeId(next),
        ));
      }
      final lines = [
        for (final l in s['lines'] as List? ?? const [])
          if (((l as Map)['text'] as String? ?? '').trim().isNotEmpty ||
              (l['photo'] as String? ?? '').trim().isNotEmpty)
            ScriptBubblePiece(
              text: (l['text'] as String? ?? '').trim(),
              delaySeconds: l['late'] == true ? 10 : 0,
              speedFactor: (l['speed'] as num? ?? 1.0).toDouble().clamp(0.4, 1.8),
              photoLabel: (l['photo'] as String? ?? '').trim().isEmpty
                  ? null
                  : (l['photo'] as String).trim(),
            ),
      ];
      if (lines.isEmpty) continue;
      nodes.add(ScriptNodeModel(
        id: id,
        eventId: event.id,
        stepOrder: (s['step'] as num? ?? 1).toInt(),
        speakerCharacterId: event.characterId,
        characterBubbles: lines,
        choices: choices,
        userFirst: [
          for (final m in s['user_first'] as List? ?? const [])
            if ((m as String).trim().isNotEmpty) ScriptBubblePiece(text: m.trim()),
        ],
      ));
    }
    if (nodes.isEmpty) {
      throw ClaudeChatException('"${event.title}" 대사를 만들지 못했어요. 다시 시도해 주세요.');
    }
    final step = (json['cutscene_step'] as num? ?? 0).toInt();
    final validStep = nodes.any((n) => n.stepOrder == step) ? step : null;
    return (nodes, validStep ?? (event.cutscenePhotoTitle != null ? nodes.first.stepOrder : null));
  }

  /// 이벤트마다 연출 하나를 고름 (같은 이벤트는 늘 같은 연출)
  /// 일상·특별 대화: 보통 / 혼잣말로 끝 / 내가 선톡 / 늦은 답장, 호감도 이벤트: 보통 / 선톡 / 늦은 답장, 엔딩: 보통
  static (_ScriptStyle, String) _scriptStyle(ScenarioEventModel event) {
    final options = switch (event.eventType) {
      ScenarioEventType.ending => [_ScriptStyle.normal],
      ScenarioEventType.daily || ScenarioEventType.special => _ScriptStyle.values,
      _ => [_ScriptStyle.normal, _ScriptStyle.normal, _ScriptStyle.userFirst, _ScriptStyle.late],
    };
    var hash = 0;
    for (final unit in event.id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final style = options[hash % options.length];
    return (
      style,
      switch (style) {
        _ScriptStyle.normal => '보통 (캐릭터가 먼저 말을 걸고 선택지로 이어짐)',
        _ScriptStyle.monologue => '혼잣말 톡 (캐릭터가 혼자 할 말만 하고 끝남)',
        _ScriptStyle.userFirst => '선톡 (유저가 먼저 톡을 보냄)',
        _ScriptStyle.late => '늦은 답장 (캐릭터 답장이 한 번 늦게 옴)',
      },
    );
  }

  Future<Map<String, dynamic>> _call({
    required AiProvider provider,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required String user,
    required Map<String, dynamic> schema,
    required int maxTokens,
  }) async {
    final (json, usage) = await callJsonModel(
      _dio,
      provider: provider,
      apiKey: apiKey, relay: relay,
      model: model,
      system: _system,
      user: user,
      schema: schema,
      maxTokens: maxTokens,
      refusalMessage: 'AI가 이 설정으로는 대본을 만들지 않았어요. 설정을 바꿔 보세요.',
      truncatedMessage: '대본이 너무 길어서 중간에 끊겼어요. 대화 수를 줄여서 다시 해 보세요.',
    );
    onUsage?.call(usage);
    return json;
  }
}

/// [초보자 노트] 좋은 선택만 골랐을 때 끝까지 갈 수 있는지 미리 돌려 보고,
/// 다음 단계 점수에 못 미치면 선택지 호감도를 조금씩 올려서 맞춥니다. (AI 대본·엑셀 대본 공통)
ScenarioBundle balanceScenario(ScenarioBundle bundle) {
  var current = bundle;
  for (var round = 0; round < 8; round++) {
    if (bestPathClears(current)) return current;
    current = _scaleDeltas(current, 1.25);
  }
  return current;
}

/// 매 장면 가장 호감도가 높은 선택지를 골랐을 때 엔딩까지 가는지 (채팅방 진행 순서와 같은 규칙)
bool bestPathClears(ScenarioBundle bundle) {
  var affection = 0;
  final flags = <String>{};
  final done = <String>[];

  bool unlocked(ScenarioEventModel e) {
    final range = bundle.affectionRangeOf(e);
    return affection >= range.min &&
        (range.max == null || affection <= range.max!) &&
        e.requiredFlags.every(flags.contains);
  }

  ScenarioEventModel? pick(bool Function(ScenarioEventModel) kind) =>
      bundle.events.where((e) => kind(e) && !done.contains(e.id) && unlocked(e)).firstOrNull;

  void play(ScenarioEventModel e) {
    var node = bundle.firstNodeOf(e.id);
    var guard = 0;
    while (node != null && guard++ < 50) {
      if (node.choices.isEmpty) break;
      final best = node.choices.reduce((a, b) => b.affectionDelta > a.affectionDelta ? b : a);
      affection = (affection + best.affectionDelta).clamp(0, 100);
      if (best.addFlag != null) flags.add(best.addFlag!);
      node = best.nextNodeId != null ? bundle.nodes[best.nextNodeId] : null;
    }
    done.add(e.id);
  }

  for (var guard = 0; guard < bundle.events.length * 2 + 2; guard++) {
    final last = done.isEmpty ? null : bundle.events.where((e) => e.id == done.last).firstOrNull;
    ScenarioEventModel? next;
    if (last?.isAffectionEvent ?? false) next = pick((e) => e.isDaily);
    next ??= pick((e) => e.isAffectionEvent);
    next ??= pick((e) => e.isDaily);
    if (next == null) break;
    play(next);
  }
  return bundle.events.where((e) => e.isAffectionEvent).every((e) => done.contains(e.id));
}

ScenarioBundle _scaleDeltas(ScenarioBundle bundle, double factor) {
  return ScenarioBundle(
    character: bundle.character,
    events: bundle.events,
    images: bundle.images,
    photoRefs: bundle.photoRefs,
    photoTriggers: bundle.photoTriggers,
    nodes: {
      for (final n in bundle.nodes.values)
        n.id: ScriptNodeModel(
          id: n.id,
          eventId: n.eventId,
          stepOrder: n.stepOrder,
          speakerCharacterId: n.speakerCharacterId,
          characterBubbles: n.characterBubbles,
          choices: [
            for (final c in n.choices)
              ChoiceOption(
                id: c.id,
                buttonLabel: c.buttonLabel,
                userBubbles: c.userBubbles,
                affectionDelta: c.affectionDelta > 0
                    ? (c.affectionDelta * factor).ceil()
                    : c.affectionDelta,
                addFlag: c.addFlag,
                nextNodeId: c.nextNodeId,
              ),
          ],
        ),
    },
  );
}

/// AI가 대본을 쓸 때 고르는 연출
enum _ScriptStyle { normal, monologue, userFirst, late }
