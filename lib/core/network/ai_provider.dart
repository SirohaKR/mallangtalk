import 'dart:convert';
import 'package:dio/dio.dart';

/// AI를 부르다 실패했을 때 화면에 그대로 보여 줄 수 있는 메시지
class ClaudeChatException implements Exception {
  final String message;
  const ClaudeChatException(this.message);
  @override
  String toString() => message;
}

/// 설정에서 고를 수 있는 모델. 가격은 100만 토큰당 달러(표준 요금, 2026-10 기준)
class AiModelOption {
  final String id;
  final String label;
  final String note;
  final double inputUsdPerMTok;
  final double outputUsdPerMTok;

  const AiModelOption(this.id, this.label, this.note, this.inputUsdPerMTok, this.outputUsdPerMTok);
}

/// [초보자 노트] 내 키(BYOK)로 부를 수 있는 AI 회사. 설정 화면 드롭다운에 이 순서로 나와요.
/// 모델 이름과 가격은 회사가 자주 바꾸니, 목록에 없는 모델은 설정에서 '직접 입력'으로 쓸 수 있어요.
enum AiProvider {
  claude(
    'Claude (Anthropic)',
    'sk-ant-로 시작하는 Claude API 키',
    'console.anthropic.com에서 발급',
    [
      AiModelOption('claude-opus-5-5', 'Claude Opus 5.5', '가장 자연스러움', 4, 20),
      AiModelOption('claude-sonnet-5-5', 'Claude Sonnet 5.5', '균형', 2, 10),
      AiModelOption('claude-haiku-5-5', 'Claude Haiku 5.5', '가장 저렴', 0.10, 0.50),
    ],
  ),
  openai(
    'ChatGPT (OpenAI)',
    'sk-로 시작하는 OpenAI API 키',
    'platform.openai.com에서 발급',
    [
      AiModelOption('gpt-6-astra', 'GPT-6 Astra', '가장 똑똑함 · 비쌈', 10, 50),
      AiModelOption('gpt-6.1-sol', 'GPT-6.1 Sol', '균형', 2, 10),
      AiModelOption('gpt-6-luna', 'GPT-6 Luna', '가장 저렴', 0.10, 0.50),
    ],
  ),
  gemini(
    'Gemini (Google)',
    'AIza로 시작하는 Gemini API 키',
    'aistudio.google.com에서 발급 · Flash 계열은 무료 한도 있음',
    [
      AiModelOption('gemini-4-argon', 'Gemini 4 Argon', '가장 똑똑함 · 12월부터 2배', 2, 10),
      AiModelOption('gemini-3.8-flash', 'Gemini 3.8 Flash', '균형 · 무료 한도 있음', 0.75, 3.75),
      AiModelOption('gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', '가장 저렴 · 무료 한도 있음', 0.30, 2.50),
    ],
  );

  const AiProvider(this.label, this.keyHint, this.keyNote, this.models);

  final String label;
  final String keyHint;
  final String keyNote;
  final List<AiModelOption> models;

  String get defaultModel => models.first.id;

  static AiProvider byName(String? name) =>
      AiProvider.values.where((p) => p.name == name).firstOrNull ?? AiProvider.claude;

  /// 목록에 있는 모델이면 그 정보, 직접 입력한 모델이면 null
  AiModelOption? option(String modelId) => models.where((m) => m.id == modelId).firstOrNull;
}

/// 한 번 부를 때 쓴 토큰 수 (사용량·금액 계산용)
class AiUsage {
  final int inputTokens;
  final int outputTokens;
  const AiUsage(this.inputTokens, this.outputTokens);
}

/// [초보자 노트] 회사마다 다른 API 모양을 하나로 맞춰 'JSON 하나 받아오기'만 하게 해 주는 함수입니다.
/// system·user 글과 JSON 모양(schema)을 주면, 그 모양대로 채운 JSON을 돌려줘요.
/// 지금은 브라우저에서 바로 부르고, 서버(4단계)가 생기면 이 함수 안의 주소만 서버 중계로 바꾸면 됩니다.
Future<(Map<String, dynamic>, AiUsage)> callJsonModel(
  Dio dio, {
  required AiProvider provider,
  required String apiKey,
  required String model,
  required String system,
  required String user,
  required Map<String, dynamic> schema,
  required int maxTokens,
  String effort = 'medium',
  String refusalMessage = 'AI가 이 내용에는 답하지 않았어요.',
  String truncatedMessage = 'AI 답이 너무 길어서 중간에 끊겼어요.',
  String unreadableMessage = 'AI 응답을 읽지 못했어요. 다시 시도해 주세요.',
}) async {
  try {
    final (text, usage) = switch (provider) {
      AiProvider.claude => await _claude(dio, apiKey, model, system, user, schema, maxTokens, effort,
          refusalMessage, truncatedMessage),
      AiProvider.openai => await _openai(dio, apiKey, model, system, user, schema, maxTokens,
          refusalMessage, truncatedMessage),
      AiProvider.gemini => await _gemini(dio, apiKey, model, system, user, schema, maxTokens,
          refusalMessage, truncatedMessage),
    };
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('not an object');
    return (json, usage);
  } on FormatException {
    throw ClaudeChatException(unreadableMessage);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final apiMessage = body is Map ? (body['error']?['message'] as String?) : null;
    throw ClaudeChatException(switch (status) {
      401 || 403 => 'API 키가 올바르지 않아요. 설정에서 다시 확인해 주세요.',
      404 => '모델 "$model"을 찾지 못했어요. 설정에서 모델 이름을 확인해 주세요.',
      429 => '요청이 너무 많거나 크레딧이 부족해요. 잠시 후 다시 시도해 주세요.',
      _ => 'AI 호출 실패${status != null ? ' ($status)' : ''}: ${apiMessage ?? e.message ?? '네트워크 오류'}',
    });
  }
}

/// 안전 분류기가 거절하면 서버가 알맞은 다른 Claude 모델로 대신 답하게 함 (Haiku는 미지원)
bool claudeSupportsFallback(String model) =>
    model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';

Future<(String, AiUsage)> _claude(Dio dio, String apiKey, String model, String system, String user,
    Map<String, dynamic> schema, int maxTokens, String effort, String refusal, String truncated) async {
  final fallback = claudeSupportsFallback(model);
  final response = await dio.post<Map<String, dynamic>>(
    'https://api.anthropic.com/v1/messages',
    options: Options(headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      // 브라우저에서 바로 호출할 때 필요한 헤더 (서버 중계로 바꾸면 제거)
      'anthropic-dangerous-direct-browser-access': 'true',
      if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    }),
    data: {
      'model': model,
      'max_tokens': maxTokens,
      if (fallback) 'fallbacks': 'default',
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
      'output_config': {
        'effort': effort,
        'format': {'type': 'json_schema', 'schema': schema},
      },
    },
  );
  final data = response.data ?? const {};
  if (data['stop_reason'] == 'refusal') throw ClaudeChatException(refusal);
  if (data['stop_reason'] == 'max_tokens') throw ClaudeChatException(truncated);
  final text = [
    for (final block in data['content'] as List? ?? const [])
      if (block is Map && block['type'] == 'text') block['text'] as String,
  ].join();
  final usage = data['usage'] as Map? ?? const {};
  return (
    text,
    AiUsage((usage['input_tokens'] as num? ?? 0).toInt(), (usage['output_tokens'] as num? ?? 0).toInt()),
  );
}

Future<(String, AiUsage)> _openai(Dio dio, String apiKey, String model, String system, String user,
    Map<String, dynamic> schema, int maxTokens, String refusal, String truncated) async {
  final response = await dio.post<Map<String, dynamic>>(
    'https://api.openai.com/v1/chat/completions',
    options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    data: {
      'model': model,
      'max_completion_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'response_format': {
        'type': 'json_schema',
        'json_schema': {'name': 'mallangtalk', 'strict': true, 'schema': schema},
      },
    },
  );
  final data = response.data ?? const {};
  final choice = (data['choices'] as List? ?? const []).firstOrNull as Map? ?? const {};
  final message = choice['message'] as Map? ?? const {};
  if (message['refusal'] != null) throw ClaudeChatException(refusal);
  if (choice['finish_reason'] == 'length') throw ClaudeChatException(truncated);
  final usage = data['usage'] as Map? ?? const {};
  return (
    message['content'] as String? ?? '',
    AiUsage((usage['prompt_tokens'] as num? ?? 0).toInt(), (usage['completion_tokens'] as num? ?? 0).toInt()),
  );
}

Future<(String, AiUsage)> _gemini(Dio dio, String apiKey, String model, String system, String user,
    Map<String, dynamic> schema, int maxTokens, String refusal, String truncated) async {
  final response = await dio.post<Map<String, dynamic>>(
    'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    options: Options(headers: {'x-goog-api-key': apiKey}),
    data: {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user},
          ],
        },
      ],
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        'responseMimeType': 'application/json',
        'responseJsonSchema': schema,
      },
    },
  );
  final data = response.data ?? const {};
  if (data['promptFeedback']?['blockReason'] != null) throw ClaudeChatException(refusal);
  final candidate = (data['candidates'] as List? ?? const []).firstOrNull as Map? ?? const {};
  final finish = candidate['finishReason'];
  if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') throw ClaudeChatException(refusal);
  if (finish == 'MAX_TOKENS') throw ClaudeChatException(truncated);
  final text = [
    for (final part in candidate['content']?['parts'] as List? ?? const [])
      if (part is Map && part['text'] is String && part['thought'] != true) part['text'] as String,
  ].join();
  final usage = data['usageMetadata'] as Map? ?? const {};
  return (
    text,
    AiUsage(
      (usage['promptTokenCount'] as num? ?? 0).toInt(),
      ((usage['candidatesTokenCount'] as num? ?? 0) + (usage['thoughtsTokenCount'] as num? ?? 0)).toInt(),
    ),
  );
}
