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
USE_SERVER_AI_KEYS=true
''');
    final config = ServerConfig.fromEnv(env);
    expect(config.keys.keys, [AiProvider.claude]);
    expect(config.accessCode, 'mallang');

    final response = await buildHandler(config, store: Store.open(':memory:'))(shelf.Request('GET', Uri.parse('http://localhost/api/health')));
    final text = await response.readAsString();
    expect(jsonDecode(text), {'ok': true, 'providers': ['claude'], 'needsAccessCode': true, 'accounts': true});
    expect(text, isNot(contains('sk-ant')));
  });

  test('접속 코드가 틀리면 AI를 부르지 않음', () async {
    final adapter = _FakeAdapter(_claudeReply);
    final handler = buildHandler(
      const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}, accessCode: 'mallang', useServerAiKeys: true),
      store: Store.open(':memory:'),
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
      const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}, accessCode: 'mallang', useServerAiKeys: true),
      store: Store.open(':memory:'),
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
    final handler = buildHandler(const ServerConfig(keys: {AiProvider.claude: 'sk-ant-test'}, useServerAiKeys: true),
        store: Store.open(':memory:'));
    final response = await handler(_post({..._body, 'provider': 'gemini'}));
    expect(response.statusCode, 400);
    expect((await _read(response))['error'], contains('Gemini'));
  });

  test('앱 화면 파일을 띄워 줌', () async {
    final dir = await Directory.systemTemp.createTemp('mallangtalk_web');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/index.html').writeAsStringSync('<html>말랑톡</html>');
    final handler = buildHandler(ServerConfig(keys: const {}, webDir: dir.path), store: Store.open(':memory:'));
    final response = await handler(shelf.Request('GET', Uri.parse('http://localhost/')));
    expect(response.statusCode, 200);
    expect(await response.readAsString(), contains('말랑톡'));
    expect(response.headers['cache-control'], 'no-cache');
  });

  test('서버 키는 기본으로 잠겨 있어서 .env에 키가 있어도 앱에 알리지 않고 대신 부르지도 않음', () async {
    final handler = buildHandler(
      ServerConfig.fromEnv({'GEMINI_API_KEY': 'AIza-test'}),
      store: Store.open(':memory:'),
    );
    final health = await _read(await handler(shelf.Request('GET', Uri.parse('http://localhost/api/health'))));
    expect(health['providers'], isEmpty);
    final response = await handler(_post({..._body, 'provider': 'gemini'}));
    expect(response.statusCode, 400);
    expect((await _read(response))['error'], contains('내 API 키'));
  });

  group('계정·캐릭터', () {
    late shelf.Handler handler;
    setUp(() => handler = buildHandler(const ServerConfig(keys: {}), store: Store.open(':memory:')));

    Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String? token}) async {
      final response = await handler(shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {if (token != null) 'authorization': 'Bearer $token'},
      ));
      final text = await response.readAsString();
      return (response.statusCode, text.startsWith('{') ? jsonDecode(text) as Map<String, dynamic> : <String, dynamic>{});
    }

    Map<String, dynamic> bundle(String id, {String avatar = ''}) => {
          'format': 'mallangtalk-scenario-v1',
          'character': {'id': id, 'name': '카이엔', 'avatar_url': avatar},
          'events': [],
          'script_nodes': [],
          'images': {'p1': 'data:image/jpeg;base64,${base64Encode([1, 2, 3])}'},
        };

    test('회원가입·로그인·로그아웃', () async {
      var (status, body) = await call('POST', '/api/auth/signup', body: {'username': 'ab', 'password': '12345678'});
      expect(status, 400); // 아이디가 너무 짧음
      (status, body) = await call('POST', '/api/auth/signup', body: {'username': 'jjaet', 'password': '1234'});
      expect(status, 400); // 비밀번호가 너무 짧음
      (status, body) = await call('POST', '/api/auth/signup',
          body: {'username': 'jjaet', 'password': 'mallang123', 'nickname': '쨋뀨'});
      expect(status, 200);
      expect(body['user'], containsPair('nickname', '쨋뀨'));
      (status, body) = await call('POST', '/api/auth/signup', body: {'username': 'JJAET', 'password': 'mallang123'});
      expect(status, 409); // 대소문자만 다른 아이디도 같은 아이디

      (status, body) = await call('POST', '/api/auth/login', body: {'username': 'jjaet', 'password': 'wrong-pass'});
      expect(status, 401);
      (status, body) = await call('POST', '/api/auth/login', body: {'username': 'jjaet', 'password': 'mallang123'});
      expect(status, 200);
      final token = body['token'] as String;
      expect((await call('GET', '/api/me', token: token)).$2['user'], containsPair('username', 'jjaet'));

      await call('POST', '/api/auth/logout', token: token);
      expect((await call('GET', '/api/me', token: token)).$1, 401);
    });

    test('만든 캐릭터를 저장하면 사진은 DB로 옮겨지고, 받아오기 목록에 보이고, 남은 못 고침', () async {
      final a = (await call('POST', '/api/auth/signup', body: {'username': 'maker', 'password': 'mallang123'})).$2['token'] as String;
      final b = (await call('POST', '/api/auth/signup', body: {'username': 'player', 'password': 'mallang123'})).$2['token'] as String;

      expect((await call('PUT', '/api/characters/char_1', body: {'bundle': bundle('char_1')})).$1, 401);
      expect((await call('PUT', '/api/characters/char_1', body: {'bundle': bundle('other')}, token: a)).$1, 400);
      final avatar = 'data:image/png;base64,${base64Encode([9, 9])}';
      var (status, body) = await call('PUT', '/api/characters/char_1', body: {'bundle': bundle('char_1', avatar: avatar)}, token: a);
      expect(status, 200);
      final saved = body['bundle'] as Map<String, dynamic>;
      final url = (saved['images'] as Map)['p1'] as String;
      expect(url, startsWith('/api/images/'));
      expect((saved['character'] as Map)['avatar_url'], startsWith('/api/images/'));
      expect(jsonEncode(saved), isNot(contains('base64')));

      final image = await handler(shelf.Request('GET', Uri.parse('http://localhost$url')));
      expect(image.statusCode, 200);
      expect(image.headers['content-type'], 'image/jpeg');
      expect(await image.read().expand((x) => x).toList(), [1, 2, 3]);

      (status, body) = await call('GET', '/api/characters', token: b);
      final list = body['characters'] as List;
      expect(list.single, containsPair('creator', 'maker'));
      expect(list.single, containsPair('mine', false));

      expect((await call('PUT', '/api/characters/char_1', body: {'bundle': bundle('char_1')}, token: b)).$1, 403);
      expect((await call('DELETE', '/api/characters/char_1', token: b)).$1, 404);

      // 비공개로 바꾸면 목록에서 빠지고, 만든 사람만 볼 수 있음
      await call('PUT', '/api/characters/char_1', body: {'bundle': bundle('char_1'), 'published': false}, token: a);
      expect(((await call('GET', '/api/characters')).$2['characters'] as List), isEmpty);
      expect((await call('GET', '/api/characters/char_1', token: b)).$1, 404);
      expect(((await call('GET', '/api/my/characters', token: a)).$2['characters'] as List).single,
          containsPair('mine', true));

      expect((await call('DELETE', '/api/characters/char_1', token: a)).$1, 200);
      expect(((await call('GET', '/api/my/characters', token: a)).$2['characters'] as List), isEmpty);
    });

    test('앱 저장값 연동: 나중에 바뀐 값이 이기고, 유저끼리는 안 섞임', () async {
      final a = (await call('POST', '/api/auth/signup', body: {'username': 'pcuser', 'password': 'mallang123'})).$2['token'] as String;
      final b = (await call('POST', '/api/auth/signup', body: {'username': 'other', 'password': 'mallang123'})).$2['token'] as String;
      expect((await call('GET', '/api/my/state')).$1, 401);
      expect(((await call('GET', '/api/my/state', token: a)).$2['items'] as Map), isEmpty);

      var (status, _) = await call('PUT', '/api/my/state', token: a, body: {
        'items': [
          {'key': 'run_doha', 'value': '{"affection":3}', 'updated_at': 200},
          {'key': 'album_doha', 'value': ['e1', 'e2'], 'updated_at': 200},
        ],
      });
      expect(status, 200);
      // 예전 값(시간이 더 이른 값)은 덮어쓰지 않음, 지운 값(null)은 그대로 기록
      await call('PUT', '/api/my/state', token: a, body: {
        'items': [
          {'key': 'run_doha', 'value': '{"affection":0}', 'updated_at': 100},
          {'key': 'album_doha', 'value': null, 'updated_at': 300},
        ],
      });
      final items = (await call('GET', '/api/my/state', token: a)).$2['items'] as Map;
      expect(items['run_doha'], {'value': '{"affection":3}', 'updated_at': 200});
      expect(items['album_doha'], {'value': null, 'updated_at': 300});
      expect(((await call('GET', '/api/my/state', token: b)).$2['items'] as Map), isEmpty);

      expect((await call('PUT', '/api/my/state', token: a, body: {
        'items': [
          {'key': '../etc', 'value': 'x', 'updated_at': 1},
        ],
      })).$1, 400);
    });
  });
}
