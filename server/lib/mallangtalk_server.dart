import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show BaseOptions, Dio;
import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'accounts.dart';
import 'repository.dart';
import 'config.dart';
import 'http/json_body.dart';
export 'config.dart';

export 'store.dart';

/// 요청 하나에 받을 글 최대 크기 (캐릭터 설정 + 대화 기록이 들어가도 넉넉하게)
const _maxBodyBytes = 8 * 1024 * 1024;

/// [초보자 노트] 서버가 하는 일:
/// - GET  /api/health  : 서버가 켜져 있는지, 어느 AI 회사 키가 있는지, 접속 코드가 필요한지 알려 줌 (키 자체는 절대 안 보냄)
/// - POST /api/ai/json : 앱 대신 .env 키로 AI를 불러서 JSON 결과만 돌려줌. 키·대화 내용은 기록(로그)하지 않음
/// - /api/auth·characters·images… : 계정·캐릭터·사진 (accounts.dart)
/// - 그 밖의 주소      : 빌드한 앱 화면 파일
Handler buildHandler(ServerConfig config,
    {required Repository store, Dio? dio}) {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 6),
      ));

  Future<Response> api(Request request) async {
    final path = request.url.path;
    if (path == 'api/ready' && request.method == 'GET') {
      try {
        await store.ping();
        return _json(200, {'ok': true});
      } catch (_) {
        return _json(503, {'ok': false, 'error': '데이터 저장소에 연결할 수 없어요.'});
      }
    }
    if (path == 'api/health' && request.method == 'GET') {
      return _json(200, {
        'ok': true,
        'providers': [
          for (final p in AiProvider.values)
            if (config.activeKeys.containsKey(p)) p.name
        ],
        'needsAccessCode': config.accessCode != null,
        'accounts': true,
      });
    }
    if (path == 'api/ai/json' && request.method == 'POST')
      return _relay(request, config, client);
    final account = await accountsApi(request, store);
    if (account != null) return account;
    return _json(404, {'error': '없는 주소예요.'});
  }

  final web = config.webDir;
  final Handler app = web != null && Directory(web).existsSync()
      ? createStaticHandler(web, defaultDocument: 'index.html')
      : (_) => Response.notFound(
          '앱 화면 폴더가 없어요. flutter build web 후 WEB_DIR을 정해 주세요.');
  FutureOr<Response> handler(Request request) =>
      request.url.path.startsWith('api/') ? api(request) : app(request);
  return const Pipeline()
      .addMiddleware(_errors())
      .addMiddleware(_cors(config.allowedOrigins))
      .addMiddleware(_noCacheForAppShell())
      .addHandler(handler);
}

Middleware _errors() => (inner) => (request) async {
      try {
        return await inner(request);
      } catch (error) {
        // Do not log request bodies, tokens, database URLs, or exception details.
        stderr.writeln(
            'request_failed method=${request.method} type=${error.runtimeType}');
        return _json(500, {'error': '서버에서 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'});
      }
    };

Middleware _cors(Set<String> allowed) => (inner) => (request) async {
      final origin = request.headers['origin'];
      if (origin == null || !allowed.contains(origin)) return inner(request);
      final headers = {
        'access-control-allow-origin': origin,
        'vary': 'Origin',
        'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'access-control-allow-headers':
            'Authorization, Content-Type, ${AiRelay.accessCodeHeader}',
      };
      if (request.method == 'OPTIONS') return Response(204, headers: headers);
      return (await inner(request)).change(headers: headers);
    };

Future<Response> _relay(Request request, ServerConfig config, Dio dio) async {
  final code = config.accessCode;
  if (code != null && request.headers[AiRelay.accessCodeHeader] != code) {
    return _json(401, {'error': '접속 코드가 맞지 않아요. 설정에서 서버 접속 코드를 확인해 주세요.'});
  }
  final length = request.contentLength;
  if (length != null && length > _maxBodyBytes)
    return _json(413, {'error': '보낸 내용이 너무 커요.'});

  final body = await readJsonBody(request, _maxBodyBytes);
  if (body == null) {
    return _json(400, {'error': '요청 모양이 이상해요.'});
  }

  final provider =
      AiProvider.values.where((p) => p.name == body['provider']).firstOrNull;
  if (provider == null) return _json(400, {'error': '모르는 AI 회사예요.'});
  final key = config.activeKeys[provider];
  if (key == null) {
    return _json(400, {
      'error': config.useServerAiKeys
          ? '서버 .env에 ${provider.label} 키가 없어요. 다른 AI 회사를 고르거나 키를 넣어 주세요.'
          : '서버 키는 잠겨 있어요. 설정에서 내 API 키를 넣어 주세요.'
    });
  }
  final model = body['model'];
  final system = body['system'];
  final user = body['user'];
  final schema = body['schema'];
  final maxTokens = body['maxTokens'];
  if (model is! String ||
      system is! String ||
      user is! String ||
      schema is! Map<String, dynamic> ||
      maxTokens is! int) {
    return _json(400, {'error': '요청 모양이 이상해요.'});
  }
  final rawImages = body['images'];
  if (rawImages != null && (rawImages is! List || rawImages.any((v) => v is! String))) {
    return _json(400, {'error':'사진 형식이 이상해요.'});
  }
  final images = (rawImages as List? ?? const []).cast<String>();
  try { validateImages(images); } on ClaudeChatException catch(e) { return _json(400, {'error':e.message}); }
  final messages = body['messages'] is Map ? body['messages'] as Map : const {};

  try {
    final (json, usage) = await callJsonModel(
      dio,
      provider: provider,
      apiKey: key,
      fromBrowser: false,
      model: model,
      system: system,
      user: user,
      schema: schema,
      images: images,
      maxTokens: maxTokens.clamp(1, 64000),
      effort: body['effort'] is String ? body['effort'] as String : 'medium',
      refusalMessage: messages['refusal'] as String? ?? 'AI가 이 내용에는 답하지 않았어요.',
      truncatedMessage:
          messages['truncated'] as String? ?? 'AI 답이 너무 길어서 중간에 끊겼어요.',
      unreadableMessage:
          messages['unreadable'] as String? ?? 'AI 응답을 읽지 못했어요. 다시 시도해 주세요.',
    );
    return _json(200, {'json': json, 'usage': usage.toJson()});
  } on ClaudeChatException catch (e) {
    // 키가 틀렸다는 안내는 앱 설정이 아니라 서버 .env를 고쳐야 하니 문장을 바꿔 줌
    final message = e.message.contains('API 키가 올바르지 않아요')
        ? '서버 .env의 ${provider.label} 키가 올바르지 않아요. 키를 확인해 주세요.'
        : e.message;
    return _json(502, {'error': message});
  }
}

/// 앱 화면 파일은 새로 빌드하면 바로 바뀌도록 매번 서버에 확인하게 함 (안 바뀌었으면 304라 가벼움)
/// main.dart.js처럼 이름이 그대로인 파일을 브라우저가 몇 시간씩 옛것으로 쓰던 문제 방지
Middleware _noCacheForAppShell() => (inner) => (request) async {
      final response = await inner(request);
      if (request.url.path.startsWith('api/')) return response;
      return response.change(headers: {'cache-control': 'no-cache'});
    };

Response _json(int status, Map<String, dynamic> body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
