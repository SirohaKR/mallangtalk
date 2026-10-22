import 'package:dio/dio.dart';
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
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 6),
            ));

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
        synopsis: (o['synopsis'] as String? ?? '').trim(),
        realTime: type == ScenarioEventType.special
            ? RealTimeWindow(fromHour: from, toHour: from == to ? (from + 3) % 24 : to)
            : null,
        cutscenePhotoTitle: type == ScenarioEventType.autoStory && cutscene.isNotEmpty ? cutscene : null,
        participantCharacterIds: [characterId],
      ));
    }

    final nodes = <String, ScriptNodeModel>{};
    final finalEvents = <ScenarioEventModel>[];
    var done = 1;
    // 너무 많이 동시에 부르면 요청 한도에 걸리니 3개씩
    for (var start = 0; start < events.length; start += 3) {
      final batch = events.sublist(start, (start + 3).clamp(0, events.length));
      final results = await Future.wait([
        for (final event in batch)
          writeScript(provider: provider, apiKey: apiKey, relay: relay, model: model, character: character, event: event, outline: events),
      ]);
      for (var j = 0; j < batch.length; j++) {
        final (eventNodes, cutsceneStep) = results[j];
        nodes.addAll({for (final n in eventNodes) n.id: n});
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
${c.aiCharacterSheet}

[호감도 단계] (낮은 단계부터)
${c.affectionStages.map((s) => '- ${s.stageLabel} (${s.minScore}~${s.maxScore}점)').join('\n')}''';

  static const _system = '''
너는 메신저 연애 시뮬레이션 게임 "말랑톡"의 시나리오 작가다. 유저는 카톡으로 캐릭터와 대화하며 호감도를 쌓는다.
- 대사는 실제 카톡처럼 짧게 끊어 친다. 괄호 지문, 행동 묘사, 나레이션은 쓰지 않는다. 이모지는 거의 안 쓴다.
- 캐릭터의 말투·습관·취미가 대사마다 살아 있어야 한다. 단계보다 앞서 나가는 고백이나 스킨십은 쓰지 않는다.
- 유저는 평소 "너"라고 부르고, 이름을 부를 때만 {{user}} 라고 쓴다(앱이 플레이어 별명으로 바꿔 넣는다). 유저 성별은 정하지 않는다.
- 플레이어가 언제 접속할지 모르므로 대사에 "지금 밤 11시" 같은 정확한 시각을 쓰지 않는다.''';

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
              'synopsis': {'type': 'string', 'description': '이 대화에서 일어나는 일 2~3문장'},
              'cutscene': {'type': 'string', 'description': 'event만: 앨범에 모이는 장면(CG) 한 줄 묘사. 없으면 빈 문자열'},
              'from_hour': {'type': 'integer', 'description': 'special만: 열리는 실제 시각 시작(0~23). 나머지는 0'},
              'to_hour': {'type': 'integer', 'description': 'special만: 끝 시각(0~24, 자정을 넘기면 시작보다 작게). 나머지는 0'},
            },
            'required': ['kind', 'stage', 'title', 'time_notice', 'synopsis', 'cutscene', 'from_hour', 'to_hour'],
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
- 이벤트 중 절반 정도에는 cutscene(앨범 장면)을 넣는다. 일상 대화·특별 이벤트의 cutscene은 빈 문자열.
- 맨 마지막에 마지막 단계의 엔딩(kind=ending) 1개. 엔딩은 관계가 결실을 맺는 장면이다.
- 같은 단계 안에서는 이벤트와 일상 대화를 번갈아 배치한다.''';

    final json = await _call(provider: provider, apiKey: apiKey, relay: relay, model: model, user: user, schema: schema, maxTokens: 9000);
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
      themeColor: base.themeColor,
      typingSpeedMultiplier: base.typingSpeedMultiplier,
      affectionStages: base.affectionStages,
    );
    return (talks, character);
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
              'step': {'type': 'integer', 'description': '몇 번째 단계인지 (1부터)'},
              'lines': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'text': {'type': 'string'},
                    'speed': {'type': 'number', 'description': '0.5 툭 빠르게 ~ 1.5 망설이며 느리게'},
                    'photo': {'type': 'string', 'description': '사진을 보내는 말풍선이면 사진 묘사, 아니면 빈 문자열'},
                  },
                  'required': ['text', 'speed', 'photo'],
                  'additionalProperties': false,
                },
              },
              'choices': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'label': {'type': 'string', 'description': '선택지 버튼 요약. 예: 같이 가자고 하기'},
                    'user_messages': {'type': 'array', 'items': {'type': 'string'}},
                    'affection': {'type': 'integer'},
                    'next_scene': {'type': 'string', 'description': '이어질 장면 이름. 이 선택으로 대화가 끝나면 빈 문자열'},
                  },
                  'required': ['label', 'user_messages', 'affection', 'next_scene'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['scene', 'step', 'lines', 'choices'],
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
    final storySoFar = outline
        .map((o) => '- [${o.stageLabel ?? ''}] ${o.title}${o.id == event.id ? '  ← 지금 쓸 대화' : ''}')
        .join('\n');

    final user = '''
${_characterSheet(character)}

[전체 목차]
$storySoFar

[지금 쓸 대화]
종류: $kindText
호감도 단계: ${event.stageLabel}
제목: ${event.title}
${event.isSpecial ? '실제 시간: ${event.realTime?.label ?? ''} 에 대화방에 있는 플레이어에게만 한 번 오는 특별한 톡' : '장면 전환: ${event.timeNotice ?? ''}'}
내용: ${event.synopsis}
${event.cutscenePhotoTitle != null ? '앨범 장면(CG): ${event.cutscenePhotoTitle} → 이 장면이 떠오르는 단계를 cutscene_step으로. 좋은 선택을 하면 반드시 지나가는 단계여야 한다.' : '앨범 장면 없음 → cutscene_step은 0'}

규칙:
- 캐릭터가 먼저 톡을 보내며 시작한다. 장면마다 캐릭터 말풍선 3~5개.
- 분량: 좋은 선택을 따라 끝까지 읽었을 때 캐릭터 말풍선이 모두 합쳐 $bubbleRange개가 되게 쓴다. 짧게 끊어 치는 카톡처럼, 한 말풍선은 한두 문장.
- 선택지는 2~3개. user_messages는 유저가 보내는 짧은 톡 1~3개.
- affection: 캐릭터 마음에 쏙 드는 답 +2~+4, 무난한 답 +1, 서운한 답 0. 음수는 쓰지 않는다.${affectionBudget != null ? '\n- 좋은 답만 골랐을 때 이 대화에서 오르는 호감도 합이 약 $affectionBudget점이 되게 맞춘다.' : ''}
- 선택지가 없는 장면에서 대화가 끝난다. next_scene은 이 대화 안의 장면 이름만 쓴다.''';

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
          userBubbles: messages.isEmpty ? [ScriptBubblePiece(text: label)] : messages,
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
      ));
    }
    if (nodes.isEmpty) {
      throw ClaudeChatException('"${event.title}" 대사를 만들지 못했어요. 다시 시도해 주세요.');
    }
    final step = (json['cutscene_step'] as num? ?? 0).toInt();
    final validStep = nodes.any((n) => n.stepOrder == step) ? step : null;
    return (nodes, validStep ?? (event.cutscenePhotoTitle != null ? nodes.first.stepOrder : null));
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
