import 'dart:io';

import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:mallangtalk_server/database/sqlite_runtime.dart';
import 'package:mallangtalk_server/repository.dart';
import 'package:mallangtalk_server/database/postgres_repository.dart';

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
  final config = ServerConfig.fromEnv(env);
  final dbPath = '${config.dataDir}/mallangtalk.db';
  final Repository store;
  if (config.databaseUrl case final url?) {
    store = await PostgresRepository.open(url);
  } else {
    configureSqliteRuntime();
    store = Store.open(dbPath);
  }
  final server = await shelf_io.serve(
      buildHandler(config, store: store), InternetAddress.anyIPv4, config.port);
  final names = [
    for (final p in AiProvider.values)
      if (config.keys.containsKey(p)) p.label
  ];
  stdout.writeln('말랑톡 서버가 켜졌어요: http://localhost:${server.port}');
  stdout.writeln('  .env: ${envFile?.path ?? '없음 (환경 변수만 사용)'}');
  stdout.writeln('  DB: ${config.databaseUrl == null ? dbPath : 'PostgreSQL'}');
  stdout.writeln(config.useServerAiKeys
      ? '  서버 AI 키: ${names.isEmpty ? '없음' : names.join(', ')}'
      : '  서버 AI 키: 잠금 (각자 설정의 내 키 사용. 켜려면 USE_SERVER_AI_KEYS=true)');
  if (config.useServerAiKeys) {
    stdout.writeln(
        '  접속 코드: ${config.accessCode == null ? '없음 (누구나 서버 키 사용 가능)' : '있음'}');
  }
  stdout.writeln(
      '  앱 화면: ${Directory(config.webDir ?? '').existsSync() ? config.webDir : '없음 (API만 동작)'}');
  var stopping = false;
  Future<void> shutdown(ProcessSignal _) async {
    if (stopping) return;
    stopping = true;
    await server.close();
    await store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
