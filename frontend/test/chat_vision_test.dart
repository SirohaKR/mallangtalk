import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/claude_chat_client.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';

class _Capture implements HttpClientAdapter {
  Map? body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    body = options.data as Map;
    const text = '{"replies":["사진 잘 보여"],"affection_delta":0}';
    return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': text}
          ],
          'choices': [
            {
              'message': {'content': text}
            }
          ],
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text}
                ]
              }
            }
          ],
          'json': jsonDecode(text),
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
  const image = 'data:image/png;base64,YQ==';
  for (final provider in AiProvider.values) {
    test('${provider.name}에 사진 설명뿐 아니라 이미지 바이트를 전달', () async {
      final adapter = _Capture();
      final client = ClaudeChatClient(dio: Dio()..httpClientAdapter = adapter);
      await client.reply(
          provider: provider,
          apiKey: 'test',
          model: 'test',
          character: const CharacterModel(
              id: 'c',
              creatorId: 'u',
              name: '캐릭터',
              statusMessage: '',
              avatarUrl: '',
              worldviewPrompt: '',
              affectionStages: []),
          stageLabel: null,
          currentEventTitle: null,
          history: [
            ChatMessageLog(
                id: 'photo',
                isUser: true,
                speakerCharacterId: 'user',
                speakerName: '나',
                text: '이거 어때?',
                photoLabel: '첨부한 사진',
                photoImage: image,
                timestamp: DateTime(2026))
          ],
          newUserMessages: [
            '이거 어때?'
          ]);
      final body = adapter.body!;
      switch (provider) {
        case AiProvider.claude:
          expect(body['messages'][0]['content'][0]['source']['data'], 'YQ==');
        case AiProvider.openai:
          expect(body['messages'][1]['content'][1]['image_url']['url'], image);
        case AiProvider.gemini:
          expect(body['contents'][0]['parts'][1]['inlineData']['data'], 'YQ==');
      }
    });
  }
  test('이미지 크기·형식 제한을 요청 전에 검사', () {
    expect(() => validateImages(['https://example.com/private.png']),
        throwsA(isA<ClaudeChatException>()));
    expect(() => validateImages(List.filled(4, image)),
        throwsA(isA<ClaudeChatException>()));
  });
}
