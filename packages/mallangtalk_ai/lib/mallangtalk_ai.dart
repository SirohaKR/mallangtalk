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

/// [초보자 노트] 부를 수 있는 AI 회사. 설정 화면 드롭다운에 이 순서로 나와요.
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
    'gemini-3.8-flash',
  );

  const AiProvider(this.label, this.keyHint, this.keyNote, this.models, [this._defaultModel]);

  final String label;
  final String keyHint;
  final String keyNote;
  final List<AiModelOption> models;

  final String? _defaultModel;

  /// 처음 고를 때의 모델. Gemini는 무료 한도가 있는 Flash가 기본
  String get defaultModel => _defaultModel ?? models.first.id;

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

  Map<String, dynamic> toJson() => {'input': inputTokens, 'output': outputTokens};

  factory AiUsage.fromJson(Map json) =>
      AiUsage((json['input'] as num? ?? 0).toInt(), (json['output'] as num? ?? 0).toInt());
}

/// [초보자 노트] 말랑톡 서버가 AI를 대신 불러 주는 경우의 서버 주소와 접속 코드.
/// 서버의 .env에 든 키를 쓰니까 브라우저에는 키가 없어도 돼요.
class AiRelay {
  /// 예: http://192.168.0.10:5200 (끝에 / 없이)
  final String baseUrl;

  /// 서버 .env에 ACCESS_CODE를 정해 둔 경우에만 필요
  final String? accessCode;

  const AiRelay(this.baseUrl, {this.accessCode});

  static const path = '/api/ai/json';
  static const accessCodeHeader = 'x-access-code';
}

/// [초보자 노트] 회사마다 다른 API 모양을 하나로 맞춰 'JSON 하나 받아오기'만 하게 해 주는 함수입니다.
/// system·user 글과 JSON 모양(schema)을 주면, 그 모양대로 채운 JSON을 돌려줘요.
/// [relay]를 주면 키 없이 말랑톡 서버에 대신 불러 달라고 하고, 없으면 [apiKey]로 회사 API를 바로 불러요.
/// 서버는 이 함수를 [fromBrowser] = false로 불러서 자기 .env 키로 회사 API를 부릅니다.
Future<(Map<String, dynamic>, AiUsage)> callJsonModel(
  Dio dio, {
  required AiProvider provider,
  String apiKey = '',
  AiRelay? relay,
  bool fromBrowser = true,
  required String model,
  required String system,
  required String user,
  required Map<String, dynamic> schema,
  required int maxTokens,
  String effort = 'medium',
  List<String> images = const [],
  String refusalMessage = 'AI가 이 내용에는 답하지 않았어요.',
  String truncatedMessage = 'AI 답이 너무 길어서 중간에 끊겼어요.',
  String unreadableMessage = 'AI 응답을 읽지 못했어요. 다시 시도해 주세요.',
}) async {
  try {
    validateImages(images);
    if (relay != null) {
      return await _relay(dio, relay, provider, model, system, user, schema, maxTokens, effort,
          refusalMessage, truncatedMessage, unreadableMessage, images);
    }
    Future<(String, AiUsage)> once() async => switch (provider) {
          AiProvider.claude => await _claude(dio, apiKey, model, system, user, schema, maxTokens, effort,
              refusalMessage, truncatedMessage, fromBrowser, images),
          AiProvider.openai => await _openai(dio, apiKey, model, system, user, schema, maxTokens,
              refusalMessage, truncatedMessage, images),
          AiProvider.gemini => await _gemini(dio, apiKey, model, system, user, schema, maxTokens,
              refusalMessage, truncatedMessage, images),
        };
    // 분당 한도(429)나 잠깐 붐빔(503)이면 회사가 알려 준 시간만큼 기다렸다가 몇 번 더 해 봄
    (String, AiUsage)? result;
    for (var attempt = 0; result == null; attempt++) {
      try {
        result = await once();
      } on DioException catch (e) {
        final wait = attempt < aiMaxRetries ? retryWaitOf(e, attempt) : null;
        if (wait == null) rethrow;
        await aiRetrySleep(wait);
      }
    }
    final (text, usage) = result;
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('not an object');
    return (json, usage);
  } on FormatException {
    throw ClaudeChatException(unreadableMessage);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    // 말랑톡 서버가 돌려준 오류는 이미 화면에 보여 줄 문장이라 그대로 씀
    if (relay != null && body is Map && body['error'] is String) {
      throw ClaudeChatException(body['error'] as String);
    }
    if (_isTimeout(e)) {
      throw const ClaudeChatException('AI 답이 너무 오래 걸려서 끊겼어요. 다시 보내 보거나, 설정에서 더 빠른 모델(Flash 등)로 바꿔 보세요.');
    }
    if (relay != null && status == null) {
      throw const ClaudeChatException('말랑톡 서버에 연결하지 못했어요. 서버가 켜져 있는지 확인해 주세요.');
    }
    if (status == null) {
      throw const ClaudeChatException('AI 회사 서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 보내 주세요.');
    }
    final error = body is Map ? body['error'] : null;
    final apiMessage = error is Map ? error['message'] as String? : null;
    // Gemini는 틀린 키에 400을 돌려줌
    final badKey = status == 400 && (apiMessage?.contains('API key') ?? false);
    throw ClaudeChatException(switch (status) {
      _ when badKey => 'API 키가 올바르지 않아요. 설정에서 다시 확인해 주세요.',
      401 || 403 => 'API 키가 올바르지 않아요. 설정에서 다시 확인해 주세요.',
      404 => '모델 "$model"을 찾지 못했어요. 설정에서 모델 이름을 확인해 주세요.',
      429 when _isZeroQuota(body) =>
        '"$model"은 무료 등급 키로는 쓸 수 없는 모델이에요. 설정에서 Flash 모델로 바꾸거나 결제를 연결해 주세요.',
      429 when _isDailyQuota(body) =>
        '오늘 쓸 수 있는 무료 한도를 다 썼어요. 내일 다시 하거나, 결제를 연결한 키·다른 모델로 바꿔 주세요.',
      429 => '요청이 너무 많거나 크레딧이 부족해요. 1~2분 뒤에 다시 시도해 주세요.',
      503 => 'AI 회사 서버가 지금 붐벼요. 잠시 후 다시 시도해 주세요.',
      _ => 'AI 호출 실패 ($status)${apiMessage != null ? ': $apiMessage' : '. 잠시 후 다시 시도해 주세요.'}',
    });
  }
}

bool _isTimeout(DioException e) =>
    e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    e.type == DioExceptionType.sendTimeout;

/// [초보자 노트] AI를 부를 때 쓰는 기다림 시간. 웹(브라우저)에서는 dio의 connectTimeout이
/// '응답 헤더가 올 때까지'라서 AI가 답을 다 만들 때까지 걸리는 시간과 같아요.
/// 그래서 웹에서는 connectTimeout을 두지 않고 receiveTimeout 하나로 전체 시간을 재요.
BaseOptions aiDioOptions({required Duration total, required bool web}) => BaseOptions(
      connectTimeout: web ? null : const Duration(seconds: 15),
      receiveTimeout: total,
    );

/// 안전 분류기가 거절하면 서버가 알맞은 다른 Claude 모델로 대신 답하게 함 (Haiku는 미지원)
bool claudeSupportsFallback(String model) =>
    model == 'claude-opus-5-5' || model == 'claude-sonnet-5-5';

/// 한도에 걸렸을 때 다시 해 볼 최대 횟수
const aiMaxRetries = 3;

/// 다시 하기 전에 기다리는 함수 (테스트에서는 바로 넘어가게 바꿈)
Future<void> Function(Duration) aiRetrySleep = Future<void>.delayed;

/// 다시 해 볼 만한 오류면 기다릴 시간, 아니면 null
/// - 429(분당 한도)·503(붐빔)만 다시 함. 하루 한도를 다 쓴 경우는 기다려도 안 풀리니 바로 실패
/// - Gemini는 오류 안에 retryDelay("37s")를, Claude·OpenAI는 retry-after 헤더를 알려 줌
Duration? retryWaitOf(DioException e, int attempt) {
  final status = e.response?.statusCode;
  if (status != 429 && status != 503) return null;
  final body = e.response?.data;
  if (status == 429 && (_isDailyQuota(body) || _isZeroQuota(body))) return null;
  Duration? hinted;
  final error = body is Map ? body['error'] : null;
  final details = error is Map ? error['details'] : null;
  if (details is List) {
    for (final d in details) {
      final delay = d is Map ? d['retryDelay'] : null;
      final seconds = delay is String ? double.tryParse(delay.replaceAll('s', '')) : null;
      if (seconds != null) hinted = Duration(milliseconds: (seconds * 1000).ceil() + 500);
    }
  }
  final header = int.tryParse(e.response?.headers.value('retry-after') ?? '');
  if (hinted == null && header != null) hinted = Duration(seconds: header);
  final wait = hinted ?? Duration(seconds: 5 * (attempt + 1) * (attempt + 1)); // 5초, 20초, 45초
  return wait > const Duration(seconds: 90) ? const Duration(seconds: 90) : wait;
}

/// 무료 등급에서 아예 쓸 수 없는 모델인지 (Gemini가 "limit: 0"이라고 알려 줌)
bool _isZeroQuota(Object? body) {
  final error = body is Map ? body['error'] : null;
  final message = error is Map ? '${error['message']}' : '';
  return RegExp(r'limit:\s*0\b').hasMatch(message);
}

/// Gemini 무료 등급의 '하루 요청 수' 한도에 걸렸는지
bool _isDailyQuota(Object? body) {
  final error = body is Map ? body['error'] : null;
  final details = error is Map ? error['details'] : null;
  if (details is! List) return false;
  return details.any((d) =>
      d is Map &&
      (d['violations'] as List? ?? const [])
          .any((v) => v is Map && '${v['quotaId']}'.contains('PerDay')));
}

/// 서버에 대신 불러 달라고 요청. 서버도 callJsonModel로 같은 검사를 하니 여기서는 결과만 받음
Future<(Map<String, dynamic>, AiUsage)> _relay(Dio dio, AiRelay relay, AiProvider provider, String model,
    String system, String user, Map<String, dynamic> schema, int maxTokens, String effort,
    String refusal, String truncated, String unreadable, List<String> images) async {
  final response = await dio.post<Map<String, dynamic>>(
    '${relay.baseUrl}${AiRelay.path}',
    options: Options(headers: {
      if (relay.accessCode != null && relay.accessCode!.isNotEmpty) AiRelay.accessCodeHeader: relay.accessCode,
    }),
    data: {
      'provider': provider.name,
      'model': model,
      'system': system,
      'user': user,
      'schema': schema,
      'maxTokens': maxTokens,
      'effort': effort,
      if (images.isNotEmpty) 'images': images,
      'messages': {'refusal': refusal, 'truncated': truncated, 'unreadable': unreadable},
    },
  );
  final data = response.data ?? const {};
  final json = data['json'];
  if (json is! Map<String, dynamic>) throw const FormatException('no json');
  return (json, AiUsage.fromJson(data['usage'] as Map? ?? const {}));
}

Future<(String, AiUsage)> _claude(Dio dio, String apiKey, String model, String system, String user,
    Map<String, dynamic> schema, int maxTokens, String effort, String refusal, String truncated,
    bool fromBrowser, List<String> images) async {
  final fallback = claudeSupportsFallback(model);
  final response = await dio.post<Map<String, dynamic>>(
    'https://api.anthropic.com/v1/messages',
    options: Options(headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      // 브라우저에서 바로 호출할 때만 필요한 헤더
      if (fromBrowser) 'anthropic-dangerous-direct-browser-access': 'true',
      if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    }),
    data: {
      'model': model,
      'max_tokens': maxTokens,
      if (fallback) 'fallbacks': 'default',
      'system': system,
      'messages': [
        {'role': 'user', 'content': images.isEmpty ? user : [
          for (final image in images) {'type': 'image', 'source': {'type': 'base64', 'media_type': image.substring(5,image.indexOf(';')), 'data': image.substring(image.indexOf(',')+1)}},
          {'type':'text','text':user},
        ]},
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
    Map<String, dynamic> schema, int maxTokens, String refusal, String truncated, List<String> images) async {
  final response = await dio.post<Map<String, dynamic>>(
    'https://api.openai.com/v1/chat/completions',
    options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    data: {
      'model': model,
      'max_completion_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': images.isEmpty ? user : [
          {'type':'text','text':user},
          for (final image in images) {'type':'image_url','image_url':{'url':image}},
        ]},
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
    Map<String, dynamic> schema, int maxTokens, String refusal, String truncated, List<String> images) async {
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
            for (final image in images) {'inlineData': {'mimeType':image.substring(5,image.indexOf(';')), 'data':image.substring(image.indexOf(',')+1)}},
          ],
        },
      ],
      'generationConfig': {
        // Gemini는 속으로 생각하는 토큰도 출력 한도에 포함돼서, 대본이 중간에 끊기지 않게 넉넉히 줌
        'maxOutputTokens': maxTokens * 2 > 65536 ? 65536 : maxTokens * 2,
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

/// Only bounded inline images are accepted; no server-side URL fetching.
void validateImages(List<String> images) {
  if (images.length > 3) throw const ClaudeChatException('사진은 한 번에 최대 3장까지 AI에게 전달할 수 있어요.');
  for (final image in images) {
    if (!RegExp(r'^data:image/(jpeg|png|webp);base64,').hasMatch(image) || image.length > 1400000) {
      throw const ClaudeChatException('사진 형식이나 크기를 확인해 주세요.');
    }
    try { base64Decode(image.substring(image.indexOf(',')+1)); }
    on FormatException { throw const ClaudeChatException('사진을 읽지 못했어요. 다시 첨부해 주세요.'); }
  }
}
