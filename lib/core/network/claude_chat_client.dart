import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';
import 'ai_provider.dart';

export 'ai_provider.dart';

/// AI가 돌려준 자유대화 답장
class FreeChatReply {
  final List<String> bubbles;
  final int affectionDelta;

  const FreeChatReply({required this.bubbles, required this.affectionDelta});
}

final claudeChatClientProvider = Provider<ClaudeChatClient>((ref) => ClaudeChatClient());

/// [초보자 노트] 내 AI 키(BYOK)로 고른 AI(Claude·ChatGPT·Gemini)에게 캐릭터 답장을 받아오는 클라이언트입니다.
/// Dart용 공식 SDK가 없어서 dio로 각 회사 API를 직접 부릅니다 (ai_provider.dart의 callJsonModel).
/// 지금은 서버가 없어서 브라우저에서 바로 호출하지만, 4단계에서 Dart 서버가 생기면
/// 기획(README)대로 서버가 중계하도록 주소만 서버로 바꾸면 됩니다. (서버는 키를 저장·로그하지 않음)
class ClaudeChatClient {
  ClaudeChatClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 90),
            ));

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
    },
    'required': ['replies', 'affection_delta'],
    'additionalProperties': false,
  };

  Future<FreeChatReply> reply({
    AiProvider provider = AiProvider.claude,
    required String apiKey,
    required String model,
    required CharacterModel character,
    required String stageLabel,
    required String? currentEventTitle,
    required List<ChatMessageLog> history,
    required List<String> newUserMessages,
    String userName = '너',
    String userIntro = '',
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
이름(별명): $userName${userIntro.isNotEmpty ? '\n소개: $userIntro' : ''}

[현재 관계]
${character.name}에게 유저는 지금 "$stageLabel" 단계다.${currentEventTitle != null ? '\n지금 이야기 장면: "$currentEventTitle"' : ''}

[답장 규칙]
- 실제 카톡처럼 짧게 1~4개 말풍선으로 끊어서 보낸다. 괄호 지문, 행동 묘사, 이모지 남발은 쓰지 않는다.
- 캐릭터의 말투와 습관을 유지하고, 관계 단계보다 앞서 나가는 고백이나 스킨십 얘기는 하지 않는다.
- affection_delta는 유저 말에 대한 캐릭터의 속마음 반응이다. 평범한 대화는 0~1, 설레거나 감동하면 2~3, 무례하거나 서운하면 음수.''';

    final user = '''
[지금까지 대화]
${transcript.isEmpty ? '(없음)' : transcript}

[방금 유저가 보낸 톡]
${newUserMessages.join('\n')}''';

    final (json, _) = await callJsonModel(
      _dio,
      provider: provider,
      apiKey: apiKey,
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

  FreeChatReply _parse(Map<String, dynamic> json) {
    final bubbles = [
      for (final r in json['replies'] as List? ?? const [])
        if ((r as String).trim().isNotEmpty) r.trim(),
    ].take(4).toList();
    if (bubbles.isEmpty) throw const ClaudeChatException('AI 답장을 읽지 못했어요. 다시 보내 주세요.');
    final delta = (json['affection_delta'] as num? ?? 0).toInt().clamp(-3, 3);
    return FreeChatReply(bubbles: bubbles, affectionDelta: delta);
  }
}
