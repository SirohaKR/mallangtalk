import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// 회사 API 대신 정해 둔 답을 돌려주고, 서버가 보낸 요청을 기록하는 가짜 연결
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions options) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(reply(options)), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _claudeReply(RequestOptions _) => {
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'text', 'text': '{"replies":["안녕"],"affection_delta":1}'},
      ],
      'usage': {'input_tokens': 120, 'output_tokens': 30},
    };

shelf.Request _post(Map<String, dynamic> body, {String? code}) => shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/ai/json'),
      body: jsonEncode(body),
      headers: {if (code != null) AiRelay.accessCodeHeader: code},
    );

const _body = {
  'provider': 'claude',
  'model': 'claude-haiku-5-5',
  'system': '너는 캐릭터야',
  'user': '안녕',
  'schema': {'type': 'object'},
  'maxTokens': 4000,
  'effort': 'low',
};

Future<Map<String, dynamic>> _read(shelf.Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  test('.env 파일을 읽고 키가 있는 회사만 알려 줌 (키 자체는 안 보냄)', () async {
    final env = parseDotEnv('''
# 메모
ANTHROPIC_API_KEY="sk-ant-test"
GEMINI_API_KEY=
export ACCESS_CODE='mallang'
''');
    final config = ServerConfig.fromEnv(env);
    expect(config.keys.keys, [AiProvider.claude]);
    expect(config.accessCode, 'mallang');

    final response = await buildHandler(config)(shelf.Request('GET', Uri.parse('http://localhost/api/health')));
    final text = await response.readAsString();
    expect(jsonDecode(text), {'ok': true, 'providers': ['claude'], 'needsAccessCode': true});
    expect(text, isNot(contains('sk-ant')));
  });

  test('접속 코드가 틀리면 AI를 부르지 않음', () async {
    final adapter = _FakeAdapter(_claudeReply);
    final handler = buildHandler(
      const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}, accessCode: 'mallang'),
      dio: Dio()..httpClientAdapter = adapter,
    );
    final response = await handler(_post(_body, code: 'wrong'));
    expect(response.statusCode, 401);
    expect((await _read(response))['error'], contains('접속 코드'));
    expect(adapter.requests, isEmpty);
  });

  test('.env 키로 Claude를 대신 불러서 JSON과 사용량만 돌려줌', () async {
    final adapter = _FakeAdapter(_claudeReply);
    final handler = buildHandler(
      const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}, accessCode: 'mallang'),
      dio: Dio()..httpClientAdapter = adapter,
    );
    final response = await handler(_post(_body, code: 'mallang'));
    expect(response.statusCode, 200);
    expect(await _read(response), {
      'json': {'replies': ['안녕'], 'affection_delta': 1},
      'usage': {'input': 120, 'output': 30},
    });
    final sent = adapter.requests.single;
    expect(sent.uri.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-ant-test');
    expect(sent.headers.containsKey('anthropic-dangerous-direct-browser-access'), isFalse);
    expect((sent.data as Map)['model'], 'claude-haiku-5-5');
  });

  test('서버에 키가 없는 회사를 고르면 알기 쉬운 안내', () async {
    final handler = buildHandler(const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}));
    final response = await handler(_post({..._body, 'provider': 'gemini'}));
    expect(response.statusCode, 400);
    expect((await _read(response))['error'], contains('Gemini'));
  });

  test('앱 화면 파일을 띄워 줌', () async {
    final dir = await Directory.systemTemp.createTemp('mallangtalk_web');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/index.html').writeAsStringSync('<html>말랑톡</html>');
    final handler = buildHandler(ServerConfig(keys: const {}, webDir: dir.path));
    final response = await handler(shelf.Request('GET', Uri.parse('http://localhost/')));
    expect(response.statusCode, 200);
    expect(await response.readAsString(), contains('말랑톡'));
    expect(response.headers['cache-control'], 'no-cache');
  });
}
