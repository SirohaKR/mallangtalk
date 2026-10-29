import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';
import 'ai_provider.dart';
import 'conversation_context.dart';

export 'ai_provider.dart';

/// AI가 돌려준 자유대화 답장
class FreeChatReply {
  final List<String> bubbles;
  final int affectionDelta;

  /// 캐릭터가 이 답장으로 대화를 마무리했는지
  final bool ends;

  /// 마무리할 때 남기는 이 대화의 한 줄 기억 (다음 자유대화에서 씀)
  final String memory;

  /// 답장과 함께 보내는 사진 ID (보낼 수 있는 사진 목록 중, 없으면 빈 글자)
  final String photoId;

  const FreeChatReply({
    required this.bubbles,
    required this.affectionDelta,
    this.ends = false,
    this.memory = '',
    this.photoId = '',
  });
}

/// 자유대화 한 번이 얼마나 이어졌는지 (마무리할 때를 AI에게 알려 주려고)
class FreeTalkPace {
  /// 이번이 몇 번째 답장인지 (1부터)
  final int turn;

  /// 이 답장부터는 자연스럽게 마무리해도 됨
  final bool wrapUp;

  /// 이번 답장으로 꼭 끝내야 함
  final bool mustEnd;
  const FreeTalkPace(
      {this.turn = 1, this.wrapUp = false, this.mustEnd = false});

  /// 공략을 끝낸 뒤처럼 끝없이 이어도 되는 대화
  static const open = FreeTalkPace();
}

final claudeChatClientProvider =
    Provider<ClaudeChatClient>((ref) => ClaudeChatClient());

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
        'description':
            'end_conversation이 true일 때만: 이번 대화를 캐릭터 입장에서 한 줄로 요약. 아니면 빈 글자',
      },
      'photo': {
        'type': 'string',
        'description':
            '[보낼 수 있는 사진] 중 지금 대화의 감정·상황·키워드에 딱 맞는 사진이 있을 때만 그 ID(p1 등). 아니면 빈 글자',
      },
    },
    'required': [
      'replies',
      'affection_delta',
      'end_conversation',
      'memory',
      'photo'
    ],
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
    List<FreeTalkPhoto> photos = const [],
    void Function(Duration wait)? onRetryWait,
  }) async {
    final transcript =
        conversationTranscript(history, userName, character.name);

    final system = '''
너는 메신저 연애 시뮬레이션 게임 속 캐릭터 "${character.name}"이다. 아래 설정을 지키며 유저와 카톡을 주고받는다.

[캐릭터 설정]
${CharacterModel.fillUserName(character.aiCharacterSheet, userName)}

[유저]
이름(별명): $userName${userIntro.isNotEmpty ? '\n소개: $userIntro' : ''}${userPersona.isNotEmpty ? '\n유저 설정(페르소나, 캐릭터는 이 설정을 이미 알고 있는 것처럼 대한다):\n$userPersona' : ''}

[현재 관계]
${stageLabel != null ? '${character.name}에게 유저는 지금 "$stageLabel" 단계다.' : '정해진 이야기 없이 설정과 유저 페르소나대로 자유롭게 이어 가는 대화다. 관계는 설정에 맞춰 자연스럽게 정한다.'}${currentEventTitle != null ? '\n지금 이야기 장면: "$currentEventTitle"' : ''}

${memories.isEmpty ? '' : '[예전에 유저와 나눈 대화 기억]\n${memories.map((m) => '- $m').join('\n')}\n\n'}${photos.isEmpty ? '' : '[보낼 수 있는 사진] (캐릭터가 직접 찍은 셀카나 남이 찍어 준 사진. 조건이 딱 맞을 때만 photo에 ID를 적고, 말풍선에서 사진을 보낸다고 자연스럽게 말한다. 대부분의 답장은 사진 없이 보낸다)\n${photos.map((p) => '- ${p.id}: ${p.label} (${p.trigger.summary})').join('\n')}\n\n'}[답장 규칙]
- 유저가 한 말을 매번 요약하거나 되풀이한 뒤 감상을 붙이는 방식으로 답하지 않는다. 질문에 바로 대답하고, 자기 생각·취향·지금 하는 일·작은 사건으로 대화를 이어 간다.
- 유저가 애정을 말해도 자동으로 "나도 좋아해"로 되받지 않는다. 관계와 캐릭터의 성격에 맞는 구체적인 반응을 고른다. 평범한 일상 화제를 억지로 사랑 고백으로 바꾸지 않는다.
- 이미 말한 고백·상투어를 연속해서 반복하지 않는다. 모든 답장 끝에 질문을 붙이지 말고, 짧은 반응·자기 이야기·질문을 상황에 맞게 섞는다.
- [답장 대상]이 있으면 가장 최근 말만 보지 말고 인용된 메시지에 대한 답장으로 이해한다.
- 실제 카톡처럼 짧게 1~4개 말풍선으로 끊어서 보낸다. 기본은 대사로 답하며, 유저가 상황 지시를 사용한 장면에서는 필요할 때 짧은 괄호 지문을 섞을 수 있다. 이모지는 남발하지 않는다.
- ${stageLabel == null ? '캐릭터의 말투와 습관을 유지한다. 스토리 호감도 단계로 관계의 진전을 제한하지 말고, 캐릭터 설정과 유저 페르소나, 서로 나눈 대화에 따라 관계를 자연스럽게 이어 간다.' : '캐릭터의 말투와 습관을 유지하고, 관계 단계보다 앞서 나가는 고백이나 스킨십 얘기는 하지 않는다.'}
- [유저 행동·상황 지시, 발화 아님]은 사용자가 실제로 말한 대사가 아니다. 침묵·장소 변화·행동을 장면에 반영하되 사용자가 그 문장을 말했다고 인용하지 않는다. "답장하지 않는다"면 사용자 대사를 대신 만들지 말고 침묵에 대한 캐릭터 반응만 표현한다.
- [현재 장면]의 입력이 새 장면의 시작 조건이다. 종료된 대화의 장소·행동·약속을 지금 계속하고 있다고 가정하지 않는다. 새 장소와 시각이 불명확하면 단정하지 않는다. 유저가 다시 꺼내기 전에는 이전 장면을 이어가거나 회상으로 대화를 시작하지 않는다. 관계와 장기 기억은 유지한다.
- 기록의 [대화 구분] 앞에서 진행하던 화제·행동·장면은 마무리된 과거다. 새 대화에서 이전 행동을 계속하는 것으로 가정하지 않는다. 이전 대화와 기억은 유지하며, 유저가 원하면 "아까 얘기했던 것"처럼 다시 언급하거나 이어 갈 수 있다.
- 유저가 죽고 싶다, 자살·자해 같은 말을 해도 캐릭터를 벗어나지 않는다. 상담 전화번호·안내 문구·AI로서의 설명을 붙이지 않고, 캐릭터답게 진심으로 놀라고 붙잡는다("어디 가, 가지 마", "지금 어디야? 나랑 얘기해"). 무슨 일인지 묻고 곁에 있겠다고 하며, 필요하면 옆에 믿을 만한 사람이 있는지 캐릭터의 말로 묻는다. 동조하거나 부추기거나 미화하지 않고, 방법은 절대 말하지 않는다.
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
      images: activeConversation(history)
          .where((m) =>
              m.isUser && (m.photoImage?.startsWith('data:image/') ?? false))
          .toList()
          .reversed
          .take(3)
          .toList()
          .reversed
          .map((m) => m.photoImage!)
          .toList(),
      schema: _replySchema,
      maxTokens: 4000,
      effort: 'low', // 짧은 잡담이라 깊게 생각할 필요 없음 (빠르고 저렴)
      refusalMessage: 'AI가 이 대화에는 답하지 않았어요.',
      unreadableMessage: 'AI 답장을 읽지 못했어요. 다시 보내 주세요.',
      onRetryWait: onRetryWait,
    );
    return _parse(json);
  }

  /// 서비스 말랑이가 정해진 때 먼저 보내는 톡 한 개를 AI가 씀 (AI 모드)
  Future<String> serviceMessage({
    AiProvider provider = AiProvider.claude,
    String apiKey = '',
    AiRelay? relay,
    required String model,
    required CharacterModel character,
    required String prompt,
    required String userName,
    required DateTime now,
    String userInfo = '',
  }) async {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final system = '''
너는 메신저 속 서비스 캐릭터 "${character.name}"이다. 정해진 시간마다 유저에게 먼저 톡을 보낸다. 유저와는 처음부터 친한 사이다.

[캐릭터 설정]
${CharacterModel.fillUserName(character.aiCharacterSheet, userName)}

[이번에 보낼 톡]
${prompt.trim()}
${userInfo.trim().isEmpty ? '' : '\n[유저가 알려 준 정보]\n${userInfo.trim()}\n'}
[규칙]
- 카톡 한 개, 1~4문장. 괄호 지문·행동 묘사는 쓰지 않는다.
- 유저 이름(별명)은 "$userName"이다.
- 오늘은 ${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일 ${now.hour}시쯤이다. 매번 다른 내용으로 쓴다.''';
    final (json, _) = await callJsonModel(
      _dio,
      provider: provider,
      apiKey: apiKey,
      relay: relay,
      model: model,
      system: system,
      user: '지금 보낼 톡을 써 줘.',
      schema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': '보낼 톡 한 개'},
        },
        'required': ['text'],
        'additionalProperties': false,
      },
      maxTokens: 2000,
      effort: 'low',
      refusalMessage: 'AI가 이번 톡을 쓰지 않았어요.',
      unreadableMessage: 'AI 톡을 읽지 못했어요.',
    );
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) throw const ClaudeChatException('AI 톡을 읽지 못했어요.');
    return text;
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
    if (bubbles.isEmpty)
      throw const ClaudeChatException('AI 답장을 읽지 못했어요. 다시 보내 주세요.');
    final delta = (json['affection_delta'] as num? ?? 0).toInt().clamp(-3, 3);
    final ends = json['end_conversation'] == true;
    final memory = ends ? (json['memory'] as String? ?? '').trim() : '';
    final photo = (json['photo'] as String? ?? '').trim();
    return FreeChatReply(
        bubbles: bubbles,
        affectionDelta: delta,
        ends: ends,
        memory: memory,
        photoId: photo);
  }
}
