import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';
import 'claude_chat_client.dart';

/// 제작 화면에서 적은 캐릭터 설정 (AI 생성의 재료)
class StudioBrief {
  final String name;
  final String statusMessage;
  final String personality; // 성격·말투·취미·세계관
  final String relationship; // 나와의 관계 (예: 알게 된 지 1년 된 남사친)
  final double typingSpeedMultiplier;
  final List<AffectionStage> stages;
  final int eventsPerStage;
  final int dailiesPerStage;

  const StudioBrief({
    required this.name,
    required this.statusMessage,
    required this.personality,
    required this.relationship,
    required this.typingSpeedMultiplier,
    required this.stages,
    this.eventsPerStage = 2,
    this.dailiesPerStage = 3,
  });

  String get worldviewPrompt => [
        personality.trim(),
        if (relationship.trim().isNotEmpty) '유저와의 관계: ${relationship.trim()}',
      ].where((s) => s.isNotEmpty).join('\n');

  /// 만들어질 대화 수 (호감도 이벤트 + 일상 대화 + 엔딩)
  int get totalTalks => stages.length * (eventsPerStage + dailiesPerStage) + 1;
}

/// 생성 진행 상황 (화면의 진행 막대용)
typedef StudioProgress = void Function(String message, int done, int total);

final claudeStudioClientProvider = Provider<ClaudeStudioClient>((ref) => ClaudeStudioClient());

/// [초보자 노트] 캐릭터 설정만 적으면 Claude가 호감도 단계별 이벤트·일상 대화·엔딩과 모든 대사를 만들어 주는 클라이언트입니다.
/// 1. 목차 만들기: 단계마다 이벤트 몇 개, 일상 대화 몇 개, 마지막에 엔딩 (한 번 호출)
/// 2. 대사 쓰기: 대화 하나마다 장면·말풍선·선택지 (대화 수만큼 호출, 3개씩 동시에)
/// 3. 균형 맞추기: 좋은 선택을 하면 끝까지 갈 수 있게 호감도 점수를 자동 보정
/// 키는 지금은 설정 화면의 내 키(BYOK)를 쓰고, 나중에 앱 토큰 충전 방식이 생기면 apiKey 자리만 서버 중계로 바꾸면 됩니다.
class ClaudeStudioClient {
  ClaudeStudioClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.anthropic.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 4),
            ));

  final Dio _dio;

  Future<ScenarioBundle> generate({
    required String apiKey,
    required String model,
    required StudioBrief brief,
    StudioProgress? onProgress,
  }) async {
    final characterId = 'char_${DateTime.now().millisecondsSinceEpoch}';
    final total = brief.totalTalks + 1;
    onProgress?.call('이야기 목차를 짜는 중', 0, total);

    final outline = await _outline(apiKey: apiKey, model: model, brief: brief);
    onProgress?.call('대사를 쓰는 중', 1, total);

    final events = <ScenarioEventModel>[];
    for (var i = 0; i < outline.length; i++) {
      final o = outline[i];
      final kind = o['kind'] as String;
      final type = switch (kind) {
        'daily' => ScenarioEventType.daily,
        'ending' => ScenarioEventType.ending,
        _ => ScenarioEventType.autoStory,
      };
      final cutscene = (o['cutscene'] as String? ?? '').trim();
      final stage = brief.stages.where((s) => s.stageLabel == o['stage']).firstOrNull ??
          brief.stages.last;
      events.add(ScenarioEventModel(
        id: 'evt_${i + 1}',
        characterId: characterId,
        chapterOrder: type == ScenarioEventType.ending ? 999 : i + 1,
        eventType: type,
        title: (o['title'] as String).trim(),
        timeNotice: (o['time_notice'] as String?)?.trim(),
        stageLabel: stage.stageLabel,
        cutscenePhotoTitle:
            type == ScenarioEventType.autoStory && cutscene.isNotEmpty ? cutscene : null,
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
          _script(
            apiKey: apiKey,
            model: model,
            brief: brief,
            event: event,
            synopsis: outline[events.indexOf(event)]['synopsis'] as String? ?? '',
            outline: outline,
          ),
      ]);
      for (var j = 0; j < batch.length; j++) {
        final (eventNodes, cutsceneStep) = results[j];
        nodes.addAll({for (final n in eventNodes) n.id: n});
        final e = batch[j];
        finalEvents.add(ScenarioEventModel(
          id: e.id,
          characterId: e.characterId,
          chapterOrder: e.chapterOrder,
          eventType: e.eventType,
          title: e.title,
          timeNotice: e.timeNotice,
          stageLabel: e.stageLabel,
          cutscenePhotoTitle: e.cutscenePhotoTitle,
          cutsceneTriggerStep: e.cutscenePhotoTitle != null ? cutsceneStep : null,
          participantCharacterIds: e.participantCharacterIds,
        ));
        done++;
        onProgress?.call('대사를 쓰는 중 · ${e.title}', done, total);
      }
    }

    final character = CharacterModel(
      id: characterId,
      creatorId: 'me',
      name: brief.name.trim(),
      statusMessage: brief.statusMessage.trim(),
      avatarUrl: '',
      worldviewPrompt: brief.worldviewPrompt,
      typingSpeedMultiplier: brief.typingSpeedMultiplier,
      affectionStages: brief.stages,
    );
    finalEvents.sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    return balanceScenario(ScenarioBundle(character: character, events: finalEvents, nodes: nodes));
  }

  String _characterSheet(StudioBrief brief) => '''
[캐릭터]
이름: ${brief.name}
상태메시지: ${brief.statusMessage}
${brief.worldviewPrompt}

[호감도 단계] (낮은 단계부터)
${brief.stages.map((s) => '- ${s.stageLabel} (${s.minScore}~${s.maxScore}점)').join('\n')}''';

  static const _system = '''
너는 메신저 연애 시뮬레이션 게임 "말랑톡"의 시나리오 작가다. 유저는 카톡으로 캐릭터와 대화하며 호감도를 쌓는다.
- 대사는 실제 카톡처럼 짧게 끊어 친다. 괄호 지문, 행동 묘사, 나레이션은 쓰지 않는다. 이모지는 거의 안 쓴다.
- 캐릭터의 말투·습관·취미가 대사마다 살아 있어야 한다. 단계보다 앞서 나가는 고백이나 스킨십은 쓰지 않는다.
- 유저 이름은 모르므로 "너"라고 부른다. 유저 성별은 정하지 않는다.''';

  Future<List<Map<String, dynamic>>> _outline({
    required String apiKey,
    required String model,
    required StudioBrief brief,
  }) async {
    final stageNames = [for (final s in brief.stages) s.stageLabel];
    final schema = {
      'type': 'object',
      'properties': {
        'talks': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'kind': {'type': 'string', 'enum': ['event', 'daily', 'ending']},
              'stage': {'type': 'string', 'enum': stageNames},
              'title': {'type': 'string'},
              'time_notice': {'type': 'string', 'description': '대화방 가운데 뜨는 시간 안내. 예: 화요일 밤 11:20'},
              'synopsis': {'type': 'string', 'description': '이 대화에서 일어나는 일 2~3문장'},
              'cutscene': {'type': 'string', 'description': 'event만: 앨범에 모이는 장면(CG) 한 줄 묘사. 없으면 빈 문자열'},
            },
            'required': ['kind', 'stage', 'title', 'time_notice', 'synopsis', 'cutscene'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['talks'],
      'additionalProperties': false,
    };

    final user = '''
${_characterSheet(brief)}

이 캐릭터의 이야기 목차를 짜 줘. 시간 순서대로 나열한다.
- 각 호감도 단계마다 호감도 이벤트(kind=event) ${brief.eventsPerStage}개와 일상 대화(kind=daily) ${brief.dailiesPerStage}개.
  이벤트는 관계가 한 발짝 나아가는 사건, 일상 대화는 취미·하루 얘기처럼 가벼운 잡담이다.
- 이벤트 중 절반 정도에는 cutscene(앨범 장면)을 넣는다. 일상 대화의 cutscene은 빈 문자열.
- 맨 마지막에 마지막 단계의 엔딩(kind=ending) 1개. 엔딩은 관계가 결실을 맺는 장면이다.
- 같은 단계 안에서는 이벤트와 일상 대화를 번갈아 배치한다.''';

    final json = await _call(
      apiKey: apiKey,
      model: model,
      user: user,
      schema: schema,
      maxTokens: 8000,
    );
    final talks = [for (final t in json['talks'] as List? ?? const []) t as Map<String, dynamic>];
    if (talks.where((t) => t['kind'] == 'event').isEmpty) {
      throw const ClaudeChatException('AI가 이벤트 목차를 만들지 못했어요. 다시 시도해 주세요.');
    }
    // 엔딩이 없거나 여러 개면 정리
    final endings = talks.where((t) => t['kind'] == 'ending').toList();
    talks.removeWhere((t) => t['kind'] == 'ending');
    if (endings.isNotEmpty) talks.add(endings.first);
    return talks;
  }

  Future<(List<ScriptNodeModel>, int?)> _script({
    required String apiKey,
    required String model,
    required StudioBrief brief,
    required ScenarioEventModel event,
    required String synopsis,
    required List<Map<String, dynamic>> outline,
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

    final kindText = switch (event.eventType) {
      ScenarioEventType.daily => '일상 대화 (가벼운 잡담, 장면 1~2개)',
      ScenarioEventType.ending => '엔딩 (장면 1~2개, 마지막 장면은 선택지 1개 또는 없음)',
      _ => '호감도 이벤트 (장면 2~4개, 선택에 따라 갈림길 1개 정도)',
    };
    final storySoFar = outline
        .map((o) => '- [${o['stage']}] ${o['title']}${o['title'] == event.title ? '  ← 지금 쓸 대화' : ''}')
        .join('\n');

    final user = '''
${_characterSheet(brief)}

[전체 목차]
$storySoFar

[지금 쓸 대화]
종류: $kindText
호감도 단계: ${event.stageLabel}
제목: ${event.title}
시간: ${event.timeNotice ?? ''}
내용: $synopsis
${event.cutscenePhotoTitle != null ? '앨범 장면(CG): ${event.cutscenePhotoTitle} → 이 장면이 떠오르는 단계를 cutscene_step으로. 좋은 선택을 하면 반드시 지나가는 단계여야 한다.' : '앨범 장면 없음 → cutscene_step은 0'}

규칙:
- 캐릭터가 먼저 톡을 보내며 시작한다. 장면마다 캐릭터 말풍선 2~5개.
- 선택지는 2~3개. user_messages는 유저가 보내는 짧은 톡 1~3개.
- affection: 캐릭터 마음에 쏙 드는 답 +4~+6, 무난한 답 +1~+3, 서운한 답 0. 음수는 쓰지 않는다.
- 선택지가 없는 장면에서 대화가 끝난다. next_scene은 이 대화 안의 장면 이름만 쓴다.''';

    final json = await _call(
      apiKey: apiKey,
      model: model,
      user: user,
      schema: schema,
      maxTokens: 12000,
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
    required String apiKey,
    required String model,
    required String user,
    required Map<String, dynamic> schema,
    required int maxTokens,
  }) async {
    final fallback = model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/messages',
        options: Options(headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true',
          if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
        }),
        data: {
          'model': model,
          'max_tokens': maxTokens,
          if (fallback) 'fallbacks': 'default',
          'system': _system,
          'messages': [
            {'role': 'user', 'content': user},
          ],
          'output_config': {
            'effort': 'medium',
            'format': {'type': 'json_schema', 'schema': schema},
          },
        },
      );
      final data = response.data ?? const {};
      if (data['stop_reason'] == 'refusal') {
        throw const ClaudeChatException('AI가 이 설정으로는 대본을 만들지 않았어요. 설정을 바꿔 보세요.');
      }
      if (data['stop_reason'] == 'max_tokens') {
        throw const ClaudeChatException('대본이 너무 길어서 중간에 끊겼어요. 대화 수를 줄여서 다시 해 보세요.');
      }
      final text = [
        for (final block in data['content'] as List? ?? const [])
          if (block is Map && block['type'] == 'text') block['text'] as String,
      ].join();
      return jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw const ClaudeChatException('AI 응답을 읽지 못했어요. 다시 시도해 주세요.');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final apiMessage = body is Map ? (body['error']?['message'] as String?) : null;
      throw ClaudeChatException(switch (status) {
        401 => 'API 키가 올바르지 않아요. 설정에서 다시 확인해 주세요.',
        429 => '요청이 너무 많거나 크레딧이 부족해요. 잠시 후 다시 시도해 주세요.',
        _ => 'AI 호출 실패${status != null ? ' ($status)' : ''}: ${apiMessage ?? e.message ?? '네트워크 오류'}',
      });
    }
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
