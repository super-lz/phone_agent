import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('diagnostic prompt logging redacts inline image data', () {
    final payload = OpenAiCompatibleChatClient.diagnosticPayloadForLog([
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '看看图片'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,iVBORw0KGgoAAA=='},
          },
        ],
      },
    ]);

    final text = payload.toString();
    expect(text, contains('看看图片'));
    expect(text, contains('<redacted'));
    expect(text, isNot(contains('iVBORw0KGgoAAA==')));
  });

  test(
    'stream chat fails instead of hanging when SSE stream is idle',
    () async {
      final streamController = StreamController<List<int>>();
      addTearDown(streamController.close);
      final client = OpenAiCompatibleChatClient(
        httpClient: _IdleStreamHttpClient(streamController.stream),
        streamIdleTimeout: const Duration(milliseconds: 10),
      );

      expect(
        client
            .streamChat(
              provider: ModelProviders.aliyunBailianQwenFlash,
              apiKey: 'test-key',
              messages: const [
                {'role': 'user', 'content': '你好'},
              ],
            )
            .drain<void>(),
        throwsA(
          isA<ModelRequestException>().having(
            (error) => error.isRetryable,
            'isRetryable',
            isTrue,
          ),
        ),
      );
    },
  );
}

class _IdleStreamHttpClient extends http.BaseClient {
  _IdleStreamHttpClient(this.stream);

  final Stream<List<int>> stream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(stream, 200);
  }
}
