import 'dart:ffi';
import 'dart:io';

import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/open.dart';

/// [초보자 노트] 서버 켜기: `dart run bin/server.dart` (server 폴더에서)
/// .env는 지금 폴더, 없으면 한 단계 위(저장소 맨 위) 폴더에서 찾아요. ENV_FILE로 위치를 직접 정할 수도 있어요.
Future<void> main() async {
  final envFile = [
    if (Platform.environment['ENV_FILE'] case final path?) path,
    '.env',
    '../.env',
  ].map(File.new).where((f) => f.existsSync()).firstOrNull;
  final env = {
    if (envFile != null) ...parseDotEnv(envFile.readAsStringSync()),
    ...Platform.environment,
  };
  // 앱 화면 폴더를 따로 안 정했으면 저장소의 build/web을 씀
  env['WEB_DIR'] ??= Directory('../build/web').existsSync() ? '../build/web' : 'web';

  final config = ServerConfig.fromEnv(env);
  _useSystemSqlite();
  final dbPath = '${config.dataDir}/mallangtalk.db';
  final store = Store.open(dbPath);
  final server = await shelf_io.serve(buildHandler(config, store: store), InternetAddress.anyIPv4, config.port);
  final names = [for (final p in AiProvider.values) if (config.keys.containsKey(p)) p.label];
  stdout.writeln('말랑톡 서버가 켜졌어요: http://localhost:${server.port}');
  stdout.writeln('  .env: ${envFile?.path ?? '없음 (환경 변수만 사용)'}');
  stdout.writeln('  DB: $dbPath');
  stdout.writeln(config.useServerAiKeys
      ? '  서버 AI 키: ${names.isEmpty ? '없음' : names.join(', ')}'
      : '  서버 AI 키: 잠금 (각자 설정의 내 키 사용. 켜려면 USE_SERVER_AI_KEYS=true)');
  if (config.useServerAiKeys) {
    stdout.writeln('  접속 코드: ${config.accessCode == null ? '없음 (누구나 서버 키 사용 가능)' : '있음'}');
  }
  stdout.writeln('  앱 화면: ${Directory(config.webDir ?? '').existsSync() ? config.webDir : '없음 (API만 동작)'}');
}

/// 리눅스 서버에는 보통 libsqlite3.so.0만 있어서 그 이름으로도 찾게 함
void _useSystemSqlite() {
  open.overrideFor(OperatingSystem.linux, () {
    Object? lastError;
    for (final name in [
      'libsqlite3.so',
      'libsqlite3.so.0',
      '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
      '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
      '/usr/lib/libsqlite3.so.0',
    ]) {
      try {
        return DynamicLibrary.open(name);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('SQLite를 찾지 못했어요. libsqlite3를 설치해 주세요. ($lastError)');
  });
}
