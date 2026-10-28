import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:mallangtalk_ai/mallangtalk_ai.dart';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

class _Capture implements HttpClientAdapter {
  Map? body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    body = options.data as Map;
    return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '{"ok":true}'}
          ]
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('서버 AI 중계도 사진 바이트를 전달하고 잘못된 첨부를 거절', () async {
    final store = Store.open(':memory:');
    addTearDown(store.close);
    final adapter = _Capture();
    final handler = buildHandler(
        const ServerConfig(
            keys: {AiProvider.claude: 'test'}, useServerAiKeys: true),
        store: store,
        dio: Dio()..httpClientAdapter = adapter);
    Future<shelf.Response> call(Object images) async =>
        await handler(shelf.Request('POST', Uri.parse('http://api/api/ai/json'),
            body: jsonEncode({
              'provider': 'claude',
              'model': 'test',
              'system': 's',
              'user': 'u',
              'schema': <String, dynamic>{},
              'maxTokens': 100,
              'images': images
            })));
    expect((await call(['data:image/png;base64,YQ=='])).statusCode, 200);
    expect(
        adapter.body!['messages'][0]['content'][0]['source']['data'], 'YQ==');
    expect((await call([42])).statusCode, 400);
    expect((await call(['https://example.com/image.png'])).statusCode, 400);
  });
}
