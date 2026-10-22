import 'dart:io';

import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

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
  final server = await shelf_io.serve(buildHandler(config), InternetAddress.anyIPv4, config.port);
  final names = [for (final p in AiProvider.values) if (config.keys.containsKey(p)) p.label];
  stdout.writeln('말랑톡 서버가 켜졌어요: http://localhost:${server.port}');
  stdout.writeln('  .env: ${envFile?.path ?? '없음 (환경 변수만 사용)'}');
  stdout.writeln('  AI 키: ${names.isEmpty ? '없음' : names.join(', ')}');
  stdout.writeln('  접속 코드: ${config.accessCode == null ? '없음 (누구나 사용 가능)' : '있음'}');
  stdout.writeln('  앱 화면: ${Directory(config.webDir ?? '').existsSync() ? config.webDir : '없음 (API만 동작)'}');
}
