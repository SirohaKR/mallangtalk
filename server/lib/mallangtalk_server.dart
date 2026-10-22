import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show BaseOptions, Dio;
import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'accounts.dart';
import 'store.dart';

export 'store.dart';

/// [초보자 노트] 서버 설정. 값은 .env 파일(또는 환경 변수)에서 읽어요.
class ServerConfig {
  /// AI 회사별 키. 비어 있는 회사는 서버로 부를 수 없음
  final Map<AiProvider, String> keys;

  /// 정해 두면 앱에서 이 코드를 넣어야 AI를 부를 수 있음 (남이 내 키를 쓰지 못하게)
  final String? accessCode;

  /// 빌드한 앱 화면(flutter build web 결과) 폴더. 없으면 API만 동작
  final String? webDir;

  final int port;

  /// DB 파일(mallangtalk.db)을 둘 폴더
  final String dataDir;

  /// .env 키로 AI를 대신 불러 줄지. 지금은 꺼 두고 각자 설정의 내 키를 씀 (USE_SERVER_AI_KEYS=true면 켜짐)
  final bool useServerAiKeys;

  const ServerConfig({
    required this.keys,
    this.accessCode,
    this.webDir,
    this.port = 5200,
    this.dataDir = 'data',
    this.useServerAiKeys = false,
  });

  /// 실제로 쓸 수 있는 서버 키 (잠가 두면 비어 있음)
  Map<AiProvider, String> get activeKeys => useServerAiKeys ? keys : const {};

  /// .env 파일 내용과 환경 변수를 합쳐서 설정을 만듦 (환경 변수가 우선)
  factory ServerConfig.fromEnv(Map<String, String> env) {
    String? read(String name) {
      final value = env[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return ServerConfig(
      keys: {
        for (final (provider, name) in [
          (AiProvider.claude, 'ANTHROPIC_API_KEY'),
          (AiProvider.openai, 'OPENAI_API_KEY'),
          (AiProvider.gemini, 'GEMINI_API_KEY'),
        ])
          if (read(name) case final key?) provider: key,
      },
      accessCode: read('ACCESS_CODE'),
      webDir: read('WEB_DIR'),
      port: int.tryParse(read('PORT') ?? '') ?? 5200,
      dataDir: read('DATA_DIR') ?? 'data',
      useServerAiKeys: read('USE_SERVER_AI_KEYS')?.toLowerCase() == 'true',
    );
  }
}

/// KEY=VALUE 줄로 된 .env 파일 읽기. #으로 시작하는 줄은 메모, 값 양쪽의 따옴표는 뗌
Map<String, String> parseDotEnv(String text) {
  final result = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim().replaceFirst(RegExp(r'^export\s+'), '');
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}

/// 요청 하나에 받을 글 최대 크기 (캐릭터 설정 + 대화 기록이 들어가도 넉넉하게)
const _maxBodyBytes = 2 * 1024 * 1024;

/// [초보자 노트] 서버가 하는 일:
/// - GET  /api/health  : 서버가 켜져 있는지, 어느 AI 회사 키가 있는지, 접속 코드가 필요한지 알려 줌 (키 자체는 절대 안 보냄)
/// - POST /api/ai/json : 앱 대신 .env 키로 AI를 불러서 JSON 결과만 돌려줌. 키·대화 내용은 기록(로그)하지 않음
/// - /api/auth·characters·images… : 계정·캐릭터·사진 (accounts.dart)
/// - 그 밖의 주소      : 빌드한 앱 화면 파일
Handler buildHandler(ServerConfig config, {required Store store, Dio? dio}) {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 6),
      ));

  Future<Response> api(Request request) async {
    final path = request.url.path;
    if (path == 'api/health' && request.method == 'GET') {
      return _json(200, {
        'ok': true,
        'providers': [for (final p in AiProvider.values) if (config.activeKeys.containsKey(p)) p.name],
        'needsAccessCode': config.accessCode != null,
        'accounts': true,
      });
    }
    if (path == 'api/ai/json' && request.method == 'POST') return _relay(request, config, client);
    final account = await accountsApi(request, store);
    if (account != null) return account;
    return _json(404, {'error': '없는 주소예요.'});
  }

  final web = config.webDir;
  final Handler app = web != null && Directory(web).existsSync()
      ? createStaticHandler(web, defaultDocument: 'index.html')
      : (_) => Response.notFound('앱 화면 폴더가 없어요. flutter build web 후 WEB_DIR을 정해 주세요.');
  FutureOr<Response> handler(Request request) =>
      request.url.path.startsWith('api/') ? api(request) : app(request);
  return const Pipeline().addMiddleware(_noCacheForAppShell()).addHandler(handler);
}

Future<Response> _relay(Request request, ServerConfig config, Dio dio) async {
  final code = config.accessCode;
  if (code != null && request.headers[AiRelay.accessCodeHeader] != code) {
    return _json(401, {'error': '접속 코드가 맞지 않아요. 설정에서 서버 접속 코드를 확인해 주세요.'});
  }
  final length = request.contentLength;
  if (length != null && length > _maxBodyBytes) return _json(413, {'error': '보낸 내용이 너무 커요.'});

  final Map<String, dynamic> body;
  try {
    final text = await request.readAsString();
    if (text.length > _maxBodyBytes) return _json(413, {'error': '보낸 내용이 너무 커요.'});
    body = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    return _json(400, {'error': '요청 모양이 이상해요.'});
  }

  final provider = AiProvider.values.where((p) => p.name == body['provider']).firstOrNull;
  if (provider == null) return _json(400, {'error': '모르는 AI 회사예요.'});
  final key = config.activeKeys[provider];
  if (key == null) {
    return _json(400, {'error': config.useServerAiKeys
        ? '서버 .env에 ${provider.label} 키가 없어요. 다른 AI 회사를 고르거나 키를 넣어 주세요.'
        : '서버 키는 잠겨 있어요. 설정에서 내 API 키를 넣어 주세요.'});
  }
  final model = body['model'];
  final system = body['system'];
  final user = body['user'];
  final schema = body['schema'];
  final maxTokens = body['maxTokens'];
  if (model is! String || system is! String || user is! String || schema is! Map<String, dynamic> || maxTokens is! int) {
    return _json(400, {'error': '요청 모양이 이상해요.'});
  }
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
      maxTokens: maxTokens.clamp(1, 64000),
      effort: body['effort'] is String ? body['effort'] as String : 'medium',
      refusalMessage: messages['refusal'] as String? ?? 'AI가 이 내용에는 답하지 않았어요.',
      truncatedMessage: messages['truncated'] as String? ?? 'AI 답이 너무 길어서 중간에 끊겼어요.',
      unreadableMessage: messages['unreadable'] as String? ?? 'AI 응답을 읽지 못했어요. 다시 시도해 주세요.',
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

/// index.html과 시작 스크립트는 새로 빌드하면 바로 바뀌도록 캐시하지 않게 함
Middleware _noCacheForAppShell() => (inner) => (request) async {
      final response = await inner(request);
      final path = request.url.path;
      if (path.isEmpty || path == 'index.html' || path == 'flutter_bootstrap.js' || path == 'version.json') {
        return response.change(headers: {'cache-control': 'no-cache'});
      }
      return response;
    };

Response _json(int status, Map<String, dynamic> body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
