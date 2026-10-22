import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/mallangtalk_models.dart';

/// 설정 화면에서 고를 수 있는 Claude 모델
class ClaudeModelOption {
  final String id;
  final String label;
  final String note;

  const ClaudeModelOption(this.id, this.label, this.note);

  static const all = [
    ClaudeModelOption('claude-opus-5-5', 'Claude Opus 5.5', '가장 자연스러움 · 한 턴 약 30원'),
    ClaudeModelOption('claude-sonnet-5-5', 'Claude Sonnet 5.5', '균형 · 한 턴 약 15원'),
    ClaudeModelOption('claude-haiku-5-5', 'Claude Haiku 5.5', '가장 저렴 · 한 턴 1원 미만'),
  ];

  static const defaultId = 'claude-opus-5-5';
}

/// AI가 돌려준 자유대화 답장
class FreeChatReply {
  final List<String> bubbles;
  final int affectionDelta;

  const FreeChatReply({required this.bubbles, required this.affectionDelta});
}

class ClaudeChatException implements Exception {
  final String message;
  const ClaudeChatException(this.message);
  @override
  String toString() => message;
}

final claudeChatClientProvider = Provider<ClaudeChatClient>((ref) => ClaudeChatClient());

/// [초보자 노트] 내 AI 키(BYOK)로 Claude에게 캐릭터 답장을 받아오는 클라이언트입니다.
/// Dart용 공식 Anthropic SDK가 없어서 dio로 Messages API를 직접 부릅니다.
/// 지금은 서버가 없어서 브라우저에서 바로 호출하지만, 4단계에서 Dart 서버가 생기면
/// 기획(README)대로 서버가 중계하도록 baseUrl만 서버 주소로 바꾸면 됩니다. (서버는 키를 저장·로그하지 않음)
class ClaudeChatClient {
  ClaudeChatClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.anthropic.com',
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

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/messages',
        options: Options(headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          // 브라우저에서 바로 호출할 때 필요한 헤더 (서버 중계로 바꾸면 제거)
          'anthropic-dangerous-direct-browser-access': 'true',
          if (_supportsFallback(model)) 'anthropic-beta': 'server-side-fallback-2026-07-01',
        }),
        data: {
          'model': model,
          'max_tokens': 4000,
          // 안전 분류기가 거절하면 서버가 알맞은 다른 모델로 대신 답하게 함 (Haiku는 미지원)
          if (_supportsFallback(model)) 'fallbacks': 'default',
          'system': system,
          'messages': [
            {'role': 'user', 'content': user},
          ],
          'output_config': {
            'effort': 'low', // 짧은 잡담이라 깊게 생각할 필요 없음 (빠르고 저렴)
            'format': {'type': 'json_schema', 'schema': _replySchema},
          },
        },
      );
      return _parse(response.data ?? const {});
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

  static bool _supportsFallback(String model) =>
      model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';

  FreeChatReply _parse(Map<String, dynamic> data) {
    if (data['stop_reason'] == 'refusal') {
      throw const ClaudeChatException('AI가 이 대화에는 답하지 않았어요.');
    }
    final text = [
      for (final block in data['content'] as List? ?? const [])
        if (block is Map && block['type'] == 'text') block['text'] as String,
    ].join();
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final bubbles = [
        for (final r in json['replies'] as List? ?? const [])
          if ((r as String).trim().isNotEmpty) r.trim(),
      ].take(4).toList();
      if (bubbles.isEmpty) throw const FormatException('empty');
      final delta = (json['affection_delta'] as num? ?? 0).toInt().clamp(-3, 3);
      return FreeChatReply(bubbles: bubbles, affectionDelta: delta);
    } on FormatException {
      throw const ClaudeChatException('AI 답장을 읽지 못했어요. 다시 보내 주세요.');
    }
  }
}
