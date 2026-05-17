import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phone_agent/data/capabilities/web_capability_adapter.dart';

void main() {
  test('search uses aliyun bailian websearch mcp', () async {
    var callCount = 0;
    final adapter = WebCapabilityAdapter(
      httpClient: MockClient((request) async {
        callCount += 1;
        expect(request.url.host, 'dashscope.aliyuncs.com');
        expect(request.headers['Authorization'], 'Bearer sk-test');
        if (callCount == 1) {
          return http.Response(
            '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26"}}',
            200,
            headers: {'mcp-session-id': 'session-1'},
          );
        }
        expect(request.headers['Mcp-Session-Id'], 'session-1');
        if (callCount == 2) {
          return http.Response('', 202);
        }
        if (callCount == 3) {
          return http.Response(
            '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"web_search"}]}}',
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final params = body['params']! as Map<String, Object?>;
        final arguments = params['arguments']! as Map<String, Object?>;
        expect(arguments['query'], '阿里云新闻');
        return _mcpToolResult('搜索结果');
      }),
    );

    final result = await adapter.search({'query': '阿里云新闻'}, apiKey: 'sk-test');

    expect(result['ok'], isTrue);
    expect(result['provider'], 'aliyun_bailian_websearch_mcp');
    expect(result['content'], '搜索结果');
  });

  test('search reports api key requirement when key is missing', () async {
    final adapter = WebCapabilityAdapter(
      httpClient: MockClient((request) async {
        fail('search should not call network without api key');
      }),
    );

    final result = await adapter.search({'query': 'example'});

    expect(result['ok'], isFalse);
    expect(result['error'], 'api_key_required');
  });

  test('fetch uses aliyun bailian websearch mcp with url prompt', () async {
    var callCount = 0;
    final adapter = WebCapabilityAdapter(
      httpClient: MockClient((request) async {
        callCount += 1;
        if (callCount == 1) {
          return http.Response(
            '{}',
            200,
            headers: {'mcp-session-id': 'session-1'},
          );
        }
        if (callCount == 2) {
          return http.Response('', 202);
        }
        if (callCount == 3) {
          return http.Response(
            '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"web_search"}]}}',
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final params = body['params']! as Map<String, Object?>;
        final arguments = params['arguments']! as Map<String, Object?>;
        expect(arguments['query']!.toString(), contains('https://example.com'));
        return _mcpToolResult('网页解析结果');
      }),
    );

    final result = await adapter.fetch({
      'url': 'https://example.com',
    }, apiKey: 'sk-test');

    expect(result['ok'], isTrue);
    expect(result['provider'], 'aliyun_bailian_websearch_mcp');
    expect(result['content'], '网页解析结果');
    expect(result['url'], 'https://example.com');
  });
}

http.Response _mcpToolResult(String text) {
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 3,
        'result': {
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      }),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
