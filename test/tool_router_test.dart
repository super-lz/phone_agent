import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/tool_router.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  final tools = CapabilityRuntime().toolDefinitions;
  const router = AgentToolRouter();

  test('model decision exposes only registered candidate tools', () {
    final route = router.routeFromDecision(
      decision: const {
        'selected_tool_names': ['fake_tool', 'web_search'],
        'uses_context': false,
        'reason': 'needs current sources',
      },
      allTools: tools,
    );

    expect(route.selectedToolNames, ['web_search']);
    expect(route.index, contains('web_search'));
  });

  test(
    'tool discovery sends latest request and context to the model',
    () async {
      final chatClient = _RoutingChatClient(
        jsonEncode({
          'selected_tool_names': ['location_get_current', 'web_search'],
          'uses_context': true,
          'reason': 'continues weather task',
        }),
      );

      final route = await router.route(
        prompt: '你自己做',
        context: 'assistant: 我可以先读取当前位置，再查天气。',
        allTools: tools,
        chatClient: chatClient,
        provider: ModelProviders.aliyunBailianQwenFlash,
        apiKey: 'test-key',
      );

      expect(
        route.selectedToolNames,
        containsAll(['location_get_current', 'web_search']),
      );
      final payload =
          jsonDecode(chatClient.lastMessages.last['content']! as String)
              as Map<String, Object?>;
      expect(payload['latest_user_message'], '你自己做');
      expect(payload['recent_context'], contains('天气'));
      expect(payload['available_tools'], isA<List<Object?>>());
      expect(payload['response_schema'], isA<Map<String, Object?>>());
    },
  );

  test(
    'discussion and negation do not override a model empty decision',
    () async {
      final chatClient = _RoutingChatClient(
        jsonEncode({
          'selected_tool_names': <String>[],
          'uses_context': false,
          'reason': 'user asks for an explanation only',
        }),
      );

      final route = await router.route(
        prompt: '解释一下如何创建网页，暂时不要创建，也不要调用工具。',
        context: 'assistant: project_create_web_app 可以生成一个本地网页。',
        allTools: tools,
        chatClient: chatClient,
        provider: ModelProviders.aliyunBailianQwenFlash,
        apiKey: 'test-key',
      );

      expect(route.tools, isEmpty);
      expect(route.selectedToolNames, isEmpty);
    },
  );

  test('quoted tool names and JSON do not activate keyword fallback', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'uses_context': false,
        'reason': 'quoted example',
      }),
    );

    final route = await router.route(
      prompt: '文档里写着 {"tool":"memory_create"}，这是什么意思？',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, isEmpty);
  });

  test('routing failure returns an empty candidate catalog', () async {
    final route = await router.route(
      prompt: '从相册选一张图片并创建网页',
      context: '',
      allTools: tools,
      chatClient: _FailingRoutingChatClient('router unavailable'),
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.tools, isEmpty);
    expect(route.index, contains('未暴露工具'));
  });

  test('invalid model JSON returns an empty candidate catalog', () async {
    final route = await router.route(
      prompt: '创建一个网页',
      context: '',
      allTools: tools,
      chatClient: _RoutingChatClient('not JSON'),
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.tools, isEmpty);
  });
}

class _RoutingChatClient extends OpenAiCompatibleChatClient {
  _RoutingChatClient(this.output);

  final String output;
  List<Map<String, Object?>> lastMessages = const [];

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async {
    lastMessages = messages;
    return ChatCompletionResult(ok: true, content: output);
  }
}

class _FailingRoutingChatClient extends OpenAiCompatibleChatClient {
  _FailingRoutingChatClient(this.message);

  final String message;

  @override
  Future<ChatCompletionResult> completeText({
    required ModelProviderConfig provider,
    required String apiKey,
    required List<Map<String, Object?>> messages,
  }) async => ChatCompletionResult(ok: false, content: message);
}
