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

  Future<FreeChatReply> call(
    _FakeAdapter adapter, {
    String model = 'claude-opus-5-5',
    AiProvider provider = AiProvider.claude,
    AiRelay? relay,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ClaudeChatClient(dio: dio).reply(
      provider: provider,
      apiKey: relay == null ? 'sk-ant-xyz' : '',
      relay: relay,
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

  test('ChatGPT는 Chat Completions + json_schema로 부르고 답장을 해석함', () async {
    final adapter = _FakeAdapter(200, {
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': jsonEncode({'replies': ['ㅇㅋ'], 'affection_delta': 1})},
        },
      ],
      'usage': {'prompt_tokens': 900, 'completion_tokens': 40},
    });
    final reply = await call(adapter, provider: AiProvider.openai, model: 'gpt-6.1-sol');
    expect(reply.bubbles, ['ㅇㅋ']);
    expect(adapter.lastRequest!.uri.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(adapter.lastRequest!.headers['Authorization'], 'Bearer sk-ant-xyz');
    final body = adapter.lastBody!;
    expect(body['model'], 'gpt-6.1-sol');
    expect(body['messages'][0]['role'], 'system');
    expect(body['response_format']['json_schema']['strict'], true);
  });

  test('Gemini는 generateContent + JSON 스키마로 부르고 생각 부분은 빼고 읽음', () async {
    final adapter = _FakeAdapter(200, {
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'parts': [
              {'text': '음...', 'thought': true},
              {'text': jsonEncode({'replies': ['굿밤'], 'affection_delta': 2})},
            ],
          },
        },
      ],
    });
    final reply = await call(adapter, provider: AiProvider.gemini, model: 'gemini-3.8-flash');
    expect(reply.bubbles, ['굿밤']);
    expect(adapter.lastRequest!.uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent');
    expect(adapter.lastRequest!.headers['x-goog-api-key'], 'sk-ant-xyz');
    final body = adapter.lastBody!;
    expect(body['generationConfig']['responseMimeType'], 'application/json');
    expect(body['systemInstruction']['parts'][0]['text'], contains('편한 친구'));
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

  test('말랑톡 서버로 부르면 키 없이 서버 주소로 요청하고 결과를 받음', () async {
    final adapter = _FakeAdapter(200, {
      'json': {'replies': ['서버에서 왔어'], 'affection_delta': 1},
      'usage': {'input': 10, 'output': 5},
    });
    final reply = await call(adapter,
        provider: AiProvider.gemini, relay: const AiRelay('http://nas.local:8080', accessCode: 'mallang'));

    expect(reply.bubbles, ['서버에서 왔어']);
    final req = adapter.lastRequest!;
    expect(req.uri.toString(), 'http://nas.local:8080/api/ai/json');
    expect(req.headers['x-access-code'], 'mallang');
    expect(req.headers.containsKey('x-goog-api-key'), isFalse);
    final body = adapter.lastBody!;
    expect(body['provider'], 'gemini');
    expect(body['effort'], 'low');
    expect(body['user'], contains('나도 뛸래'));
    expect(body.toString(), isNot(contains('sk-ant')));
  });

  test('서버가 돌려준 오류 문장을 그대로 보여 줌', () async {
    final adapter = _FakeAdapter(401, {'error': '접속 코드가 맞지 않아요. 설정에서 서버 접속 코드를 확인해 주세요.'});
    await expectLater(
      call(adapter, relay: const AiRelay('http://nas.local:8080')),
      throwsA(isA<ClaudeChatException>().having((e) => e.message, 'message', contains('접속 코드'))),
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
