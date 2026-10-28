import 'dart:convert';
import 'package:mallangtalk_ai/mallangtalk_ai.dart';

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
  final String? databaseUrl;
  final Set<String> allowedOrigins;

  const ServerConfig({
    required this.keys,
    this.accessCode,
    this.webDir,
    this.port = 5200,
    this.dataDir = 'data',
    this.useServerAiKeys = false,
    this.databaseUrl,
    this.allowedOrigins = const {},
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
      databaseUrl: read('DATABASE_URL'),
      allowedOrigins: (read('ALLOWED_ORIGINS') ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet(),
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
    final key =
        line.substring(0, eq).trim().replaceFirst(RegExp(r'^export\s+'), '');
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}
