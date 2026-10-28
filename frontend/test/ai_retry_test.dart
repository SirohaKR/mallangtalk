import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/ai_provider.dart';

/// 정해 둔 응답을 차례로 돌려주는 가짜 연결
class _SeqAdapter implements HttpClientAdapter {
  _SeqAdapter(this.responses);
  final List<(int, Map<String, dynamic>)> responses;
  var calls = 0;
  final bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    bodies.add(options.data);
    final (status, body) = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _geminiOk() => {
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'parts': [
              {'text': '{"ok":true}'},
            ],
          },
        },
      ],
    };

Map<String, dynamic> _geminiLimit({String quotaId = 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier', String message = 'Quota exceeded'}) => {
      'error': {
        'code': 429,
        'message': message,
        'details': [
          {
            '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
            'violations': [
              {'quotaId': quotaId},
            ],
          },
          {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '12s'},
        ],
      },
    };

void main() {
  final waits = <Duration>[];
  setUp(() {
    waits.clear();
    aiRetrySleep = (d) async => waits.add(d);
  });
  tearDown(() => aiRetrySleep = Future<void>.delayed);

  Future<Map<String, dynamic>> call(_SeqAdapter adapter, {int maxTokens = 9000}) async {
    final (json, _) = await callJsonModel(
      Dio()..httpClientAdapter = adapter,
      provider: AiProvider.gemini,
      apiKey: 'AIza-test',
      model: 'gemini-3.8-flash',
      system: 's',
      user: 'u',
      schema: const {'type': 'object'},
      maxTokens: maxTokens,
    );
    return json;
  }

  test('오래 걸려서 끊기면 영어 원문 대신 한국어 안내, 웹에서는 응답 전체 시간만 잼', () async {
    final dio = Dio()..httpClientAdapter = _TimeoutAdapter();
    await expectLater(
      callJsonModel(dio,
          provider: AiProvider.gemini, apiKey: 'k', model: 'm', system: 's', user: 'u',
          schema: const {'type': 'object'}, maxTokens: 10),
      throwsA(isA<ClaudeChatException>()
          .having((e) => e.message, 'm', contains('너무 오래 걸려서'))
          .having((e) => e.message, 'm', isNot(contains('connectTimeout')))),
    );
    final web = aiDioOptions(total: const Duration(minutes: 2), web: true);
    expect(web.connectTimeout, isNull); // 웹에서는 AI가 답을 만드는 동안 끊지 않음
    expect(web.receiveTimeout, const Duration(minutes: 2));
    expect(aiDioOptions(total: const Duration(minutes: 2), web: false).connectTimeout, const Duration(seconds: 15));
  });

  test('분당 한도(429)에 걸리면 Gemini가 알려 준 시간만큼 기다렸다가 다시 함', () async {
    final adapter = _SeqAdapter([(429, _geminiLimit()), (429, _geminiLimit()), (200, _geminiOk())]);
    expect(await call(adapter), {'ok': true});
    expect(adapter.calls, 3);
    expect(waits, [const Duration(milliseconds: 12500), const Duration(milliseconds: 12500)]);
  });

  test('effort가 low면 Gemini에게 생각을 짧게(thinkingLevel low) 하라고 하고, 기다릴 때 알려 줌', () async {
    Future<void> run(String effort) async {
      final adapter = _SeqAdapter([(429, _geminiLimit()), (200, _geminiOk())]);
      final told = <Duration>[];
      await callJsonModel(Dio()..httpClientAdapter = adapter,
          provider: AiProvider.gemini, apiKey: 'k', model: 'gemini-3.8-flash', system: 's', user: 'u',
          schema: const {'type': 'object'}, maxTokens: 10, effort: effort, onRetryWait: told.add);
      expect(told, [const Duration(milliseconds: 12500)]);
      final config = (adapter.bodies.last as Map)['generationConfig'] as Map;
      expect(config['thinkingConfig'], effort == 'low' ? {'thinkingLevel': 'low'} : isNull);
    }

    await run('low');
    await run('medium'); // 대본 만들기는 지금처럼 깊게 생각
  });

  test('계속 막히면 세 번까지만 다시 하고 알기 쉬운 안내', () async {
    final adapter = _SeqAdapter([(429, _geminiLimit())]);
    await expectLater(call(adapter),
        throwsA(isA<ClaudeChatException>().having((e) => e.message, 'm', contains('1~2분 뒤'))));
    expect(adapter.calls, 1 + aiMaxRetries);
  });

  test('하루 한도를 다 썼거나 무료로 못 쓰는 모델이면 기다리지 않고 바로 안내', () async {
    final daily = _SeqAdapter([(429, _geminiLimit(quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'))]);
    await expectLater(call(daily),
        throwsA(isA<ClaudeChatException>().having((e) => e.message, 'm', contains('오늘 쓸 수 있는 무료 한도'))));
    expect(daily.calls, 1);

    final zero = _SeqAdapter([(429, _geminiLimit(message: 'Quota exceeded for metric: x, limit: 0, model: gemini-4-argon'))]);
    await expectLater(call(zero),
        throwsA(isA<ClaudeChatException>().having((e) => e.message, 'm', contains('무료 등급 키로는 쓸 수 없는 모델'))));
    expect(zero.calls, 1);
    expect(waits, isEmpty);
  });

  test('Gemini 기본 모델은 무료 한도가 있는 Flash', () {
    expect(AiProvider.gemini.defaultModel, 'gemini-3.8-flash');
    expect(AiProvider.claude.defaultModel, 'claude-opus-5-5');
  });
}

class _TimeoutAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionTimeout(requestOptions: options, timeout: const Duration(seconds: 15));

  @override
  void close({bool force = false}) {}
}
