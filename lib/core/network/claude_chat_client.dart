import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';
import 'ai_provider.dart';

export 'ai_provider.dart';

/// AI가 돌려준 자유대화 답장
class FreeChatReply {
  final List<String> bubbles;
  final int affectionDelta;
  /// 캐릭터가 이 답장으로 대화를 마무리했는지
  final bool ends;
  /// 마무리할 때 남기는 이 대화의 한 줄 기억 (다음 자유대화에서 씀)
  final String memory;

  const FreeChatReply({required this.bubbles, required this.affectionDelta, this.ends = false, this.memory = ''});
}

/// 자유대화 한 번이 얼마나 이어졌는지 (마무리할 때를 AI에게 알려 주려고)
class FreeTalkPace {
  /// 이번이 몇 번째 답장인지 (1부터)
  final int turn;
  /// 이 답장부터는 자연스럽게 마무리해도 됨
  final bool wrapUp;
  /// 이번 답장으로 꼭 끝내야 함
  final bool mustEnd;
  const FreeTalkPace({this.turn = 1, this.wrapUp = false, this.mustEnd = false});

  /// 공략을 끝낸 뒤처럼 끝없이 이어도 되는 대화
  static const open = FreeTalkPace();
}

final claudeChatClientProvider = Provider<ClaudeChatClient>((ref) => ClaudeChatClient());

/// [초보자 노트] 내 AI 키(BYOK)로 고른 AI(Claude·ChatGPT·Gemini)에게 캐릭터 답장을 받아오는 클라이언트입니다.
/// Dart용 공식 SDK가 없어서 dio로 각 회사 API를 직접 부릅니다 (ai_provider.dart의 callJsonModel).
/// 말랑톡 서버에서 열었으면 [relay]로 서버가 .env 키로 대신 불러 주고(서버는 대화 내용을 기록하지 않음),
/// 아니면 내 키로 브라우저에서 바로 부릅니다.
class ClaudeChatClient {
  ClaudeChatClient({Dio? dio})
      : _dio = dio ??
            Dio(aiDioOptions(total: const Duration(minutes: 2), web: kIsWeb));

  final Dio _dio;

  /// 답장 JSON 모양 (structured outputs로 이 모양만 나오게 강제)
  static const _replySchema = {
    'type': 'object',
    'properties': {
      'replies': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '캐릭터가 연속으로 보내는 짧은 카톡 말풍선 1~4개',
      },
      'affection_delta': {
        'type': 'integer',
        'description': '유저의 말이 캐릭터 호감도에 준 변화. -3(크게 실망) ~ +3(크게 설렘)',
      },
      'end_conversation': {
        'type': 'boolean',
        'description': '이 답장으로 캐릭터가 대화를 마무리하면 true',
      },
      'memory': {
        'type': 'string',
        'description': 'end_conversation이 true일 때만: 이번 대화를 캐릭터 입장에서 한 줄로 요약. 아니면 빈 글자',
      },
    },
    'required': ['replies', 'affection_delta', 'end_conversation', 'memory'],
    'additionalProperties': false,
  };

  Future<FreeChatReply> reply({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String? stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
    String userName = '너',
    String userIntro = '',
    String userPersona = '',
    FreeTalkPace pace = FreeTalkPace.open,
    List<String> memories = const [],
  }) async {
    final transcript = history
        .where((m) => !m.isSystem)
        .toList()
        .reversed
        .take(30)
        .toList()
        .reversed
        .map((m) {
      final who = m.isUser ? userName : character.name;
      final photo = m.hasPhoto ? ' [사진: ${m.photoLabel}]' : '';
      return '$who: ${m.text}$photo';
    }).join('\n');

    final system = '''
너는 메신저 연애 시뮬레이션 게임 속 캐릭터 "${character.name}"이다. 아래 설정을 지키며 유저와 카톡을 주고받는다.

[캐릭터 설정]
${CharacterModel.fillUserName(character.aiCharacterSheet, userName)}

[유저]
이름(별명): $userName${userIntro.isNotEmpty ? '\n소개: $userIntro' : ''}${userPersona.isNotEmpty ? '\n유저 설정(페르소나, 캐릭터는 이 설정을 이미 알고 있는 것처럼 대한다):\n$userPersona' : ''}

[현재 관계]
${stageLabel != null ? '${character.name}에게 유저는 지금 "$stageLabel" 단계다.' : '정해진 이야기 없이 설정과 유저 페르소나대로 자유롭게 이어 가는 대화다. 관계는 설정에 맞춰 자연스럽게 정한다.'}${currentEventTitle != null ? '\n지금 이야기 장면: "$currentEventTitle"' : ''}

${memories.isEmpty ? '' : '[예전에 유저와 나눈 대화 기억]\n${memories.map((m) => '- $m').join('\n')}\n\n'}[답장 규칙]
- 실제 카톡처럼 짧게 1~4개 말풍선으로 끊어서 보낸다. 괄호 지문, 행동 묘사, 이모지 남발은 쓰지 않는다.
- 캐릭터의 말투와 습관을 유지하고, 관계 단계보다 앞서 나가는 고백이나 스킨십 얘기는 하지 않는다.
- affection_delta는 유저 말에 대한 캐릭터의 속마음 반응이다. 평범한 대화는 0~1, 설레거나 감동하면 2~3, 무례하거나 서운하면 음수.
- 작별 인사가 오가거나 화제가 자연스럽게 끝나면 캐릭터답게 마무리하고 end_conversation을 true로, memory에 이번 대화를 한 줄로 남긴다.${_paceRule(pace)}''';

    final user = '''
[지금까지 대화]
${transcript.isEmpty ? '(없음)' : transcript}

[방금 유저가 보낸 톡]
${newUserMessages.join('\n')}''';

    final (json, _) = await callJsonModel(
      _dio,
      provider: provider,
      apiKey: apiKey, relay: relay,
      model: model,
      system: system,
      user: user,
      schema: _replySchema,
      maxTokens: 4000,
      effort: 'low', // 짧은 잡담이라 깊게 생각할 필요 없음 (빠르고 저렴)
      refusalMessage: 'AI가 이 대화에는 답하지 않았어요.',
      unreadableMessage: 'AI 답장을 읽지 못했어요. 다시 보내 주세요.',
    );
    return _parse(json);
  }

  static String _paceRule(FreeTalkPace pace) {
    if (pace.mustEnd) {
      return '\n- 이번 답장으로 반드시 대화를 마무리한다. 씻으러 간다, 잠이 온다, 일이 생겼다처럼 캐릭터다운 핑계를 대고 end_conversation은 true.';
    }
    if (pace.wrapUp) {
      return '\n- 대화가 꽤 길어졌다(${pace.turn}번째 답장). 흐름을 봐서 자연스럽게 마무리를 향해 간다. 억지로 끊지는 않는다.';
    }
    return '';
  }

  FreeChatReply _parse(Map<String, dynamic> json) {
    final bubbles = [
      for (final r in json['replies'] as List? ?? const [])
        if ((r as String).trim().isNotEmpty) r.trim(),
    ].take(4).toList();
    if (bubbles.isEmpty) throw const ClaudeChatException('AI 답장을 읽지 못했어요. 다시 보내 주세요.');
    final delta = (json['affection_delta'] as num? ?? 0).toInt().clamp(-3, 3);
    final ends = json['end_conversation'] == true;
    final memory = ends ? (json['memory'] as String? ?? '').trim() : '';
    return FreeChatReply(bubbles: bubbles, affectionDelta: delta, ends: ends, memory: memory);
  }
}
