import 'dart:async';
import 'dart:convert';

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

  test(
    'openai-compatible provider posts to provider endpoint with bearer key',
    () async {
      final httpClient = _CapturingHttpClient(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
        ),
      );
      final client = OpenAiCompatibleChatClient(httpClient: httpClient);

      final result = await client.completeText(
        provider: ModelProviders.miniMax,
        apiKey: 'minimax-key',
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
      );

      expect(result.ok, isTrue);
      expect(
        httpClient.lastUrl.toString(),
        'https://api.minimaxi.com/v1/chat/completions',
      );
      expect(httpClient.lastHeaders['Authorization'], 'Bearer minimax-key');
      final body = jsonDecode(httpClient.lastBody) as Map<String, Object?>;
      expect(body['model'], 'MiniMax-M3');
      expect(body['stream'], isFalse);
    },
  );

  test(
    'anthropic provider posts messages request with version header',
    () async {
      final httpClient = _CapturingHttpClient(
        http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'claude ok'},
            ],
          }),
          200,
        ),
      );
      final client = OpenAiCompatibleChatClient(httpClient: httpClient);

      final result = await client.completeText(
        provider: ModelProviders.anthropicClaude,
        apiKey: 'claude-key',
        messages: const [
          {'role': 'system', 'content': 'system rules'},
          {'role': 'user', 'content': 'hello'},
        ],
      );

      expect(result.content, 'claude ok');
      expect(
        httpClient.lastUrl.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(httpClient.lastHeaders['x-api-key'], 'claude-key');
      expect(httpClient.lastHeaders['anthropic-version'], '2023-06-01');
      final body = jsonDecode(httpClient.lastBody) as Map<String, Object?>;
      expect(body['model'], ModelProviders.anthropicClaude.model);
      expect(body['system'], 'system rules');
      expect(body['stream'], isFalse);
    },
  );

  test('unavailable provider reports configuration-only status', () async {
    final client = OpenAiCompatibleChatClient();

    final result = await client.testConnection(
      provider: ModelProviders.xiaomiMimo,
      apiKey: 'mimo-key',
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('官方 API endpoint 尚未确认'));
  });
}

class _IdleStreamHttpClient extends http.BaseClient {
  _IdleStreamHttpClient(this.stream);

  final Stream<List<int>> stream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(stream, 200);
  }
}

class _CapturingHttpClient extends http.BaseClient {
  _CapturingHttpClient(this.response);

  final http.Response response;
  late Uri lastUrl;
  late Map<String, String> lastHeaders;
  late String lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    lastHeaders = Map<String, String>.of(request.headers);
    if (request is http.Request) {
      lastBody = request.body;
    } else {
      lastBody = '';
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
    );
  }
}
