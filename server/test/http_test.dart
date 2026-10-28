import 'dart:convert';
import 'package:mallangtalk_server/mallangtalk_server.dart';
import 'package:mallangtalk_server/http/json_body.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('JSON input limit counts streamed UTF-8 bytes, not characters',
      () async {
    final bytes = utf8.encode('{"text":"한글"}');
    final request = Request('POST', Uri.parse('http://localhost/api/test'),
        body: Stream.value(bytes));
    expect(await readJsonBody(request, bytes.length - 1), isNull);
  });
  test('CORS preflight allows only configured frontend origins', () async {
    final store = Store.open(':memory:');
    addTearDown(store.close);
    final handler = buildHandler(
        const ServerConfig(
            keys: {}, allowedOrigins: {'https://frontend.example.com'}),
        store: store);
    final allowed = await handler(Request(
        'OPTIONS', Uri.parse('http://api/api/me'),
        headers: {'origin': 'https://frontend.example.com'}));
    expect(allowed.statusCode, 204);
    expect(allowed.headers['access-control-allow-origin'],
        'https://frontend.example.com');
    final denied = await handler(Request(
        'OPTIONS', Uri.parse('http://api/api/me'),
        headers: {'origin': 'https://other.example.com'}));
    expect(denied.headers.containsKey('access-control-allow-origin'), isFalse);
  });
}
