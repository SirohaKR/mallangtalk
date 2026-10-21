import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';

/// 실제 네트워크 없이 Claude 요청 모양과 응답 해석을 확인하는 테스트입니다.
void main() {
  const character = CharacterModel(
    id: 'c',
    creatorId: 'u',
    name: '윤도하',
    statusMessage: '',
    avatarUrl: '',
    worldviewPrompt: '장난기 많은 남사친',
    affectionStages: [],
  );

  Future<FreeChatReply> call(_FakeAdapter adapter, {String model = 'claude-opus-5-5'}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.anthropic.com'))..httpClientAdapter = adapter;
    return ClaudeChatClient(dio: dio).reply(
      apiKey: 'sk-ant-xyz',
      model: model,
      character: character,
      stageLabel: '편한 친구',
      currentEventTitle: '새벽 러닝',
      history: [
        ChatMessageLog(
          id: '1', isUser: false, speakerCharacterId: 'c', speakerName: '윤도하',
          text: '6km 완주', timestamp: DateTime(2026),
        ),
      ],
      newUserMessages: ['대박', '나도 뛸래'],
    );
  }

  test('요청 헤더·본문이 Messages API 형식에 맞고 답장을 해석함', () async {
    final adapter = _FakeAdapter(200, {
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': jsonEncode({'replies': ['ㅋㅋ 진짜?', '토요일 6시 콜'], 'affection_delta': 9})},
      ],
    });
    final reply = await call(adapter);

    expect(reply.bubbles, ['ㅋㅋ 진짜?', '토요일 6시 콜']);
    expect(reply.affectionDelta, 3); // -3~3으로 잘림
    final req = adapter.lastRequest!;
    expect(req.uri.toString(), 'https://api.anthropic.com/v1/messages');
    expect(req.headers['x-api-key'], 'sk-ant-xyz');
    expect(req.headers['anthropic-version'], '2023-06-01');
    expect(req.headers['anthropic-dangerous-direct-browser-access'], 'true');
    expect(req.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    final body = adapter.lastBody!;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['fallbacks'], 'default');
    expect(body.containsKey('thinking'), isFalse);
    expect(body['output_config']['format']['type'], 'json_schema');
    expect(body['system'], contains('편한 친구'));
    expect(body['messages'][0]['content'], contains('윤도하: 6km 완주'));
    expect(body['messages'][0]['content'], contains('나도 뛸래'));
  });

  test('Haiku는 fallback 없이 호출', () async {
    final adapter = _FakeAdapter(200, {
      'content': [
        {'type': 'text', 'text': jsonEncode({'replies': ['ㅇㅇ'], 'affection_delta': 0})},
      ],
    });
    await call(adapter, model: 'claude-haiku-5-5');
    expect(adapter.lastRequest!.headers.containsKey('anthropic-beta'), isFalse);
    expect(adapter.lastBody!.containsKey('fallbacks'), isFalse);
  });

  test('잘못된 키와 거절은 알아들을 수 있는 메시지로', () async {
    await expectLater(
      call(_FakeAdapter(401, {'error': {'message': 'invalid x-api-key'}})),
      throwsA(isA<ClaudeChatException>().having((e) => e.message, 'message', contains('API 키'))),
    );
    await expectLater(
      call(_FakeAdapter(200, {'stop_reason': 'refusal', 'content': []})),
      throwsA(isA<ClaudeChatException>()),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.response);

  final int status;
  final Map<String, dynamic> response;
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    lastBody = options.data as Map<String, dynamic>;
    return ResponseBody.fromString(jsonEncode(response), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
