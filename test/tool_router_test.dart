import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/tool_router.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  final tools = CapabilityRuntime().toolDefinitions;
  const router = AgentToolRouter();

  test('ordinary chat can route to no tools from model decision', () {
    final route = router.routeFromDecision(
      decision: const {
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'ordinary chat',
      },
      allTools: tools,
    );

    expect(route.tools, isEmpty);
    expect(route.index, contains('未暴露工具 schema'));
  });

  test('invalid model tool names are ignored instead of guessed', () {
    final route = router.routeFromDecision(
      decision: const {
        'selected_tool_names': ['fake_tool', 'web_search'],
        'required_tool_names': ['fake_tool'],
        'uses_context': false,
        'reason': 'model picked invalid tool too',
      },
      allTools: tools,
    );

    expect(route.selectedToolNames, ['web_search']);
    expect(route.requiredToolNames, isEmpty);
  });

  test('model output routes web app creation as required tool', () {
    final route = router.routeFromModelOutput(
      jsonEncode({
        'selected_tool_names': [
          'project_create_web_app',
          'file_search_app_files',
          'file_read_app_file',
          'file_apply_text_patch',
          'artifact_create',
          'artifact_query',
        ],
        'required_tool_names': ['project_create_web_app'],
        'uses_context': false,
        'reason': 'create a local web app',
      }),
      allTools: tools,
    );

    expect(route.selectedToolNames, contains('project_create_web_app'));
    expect(route.selectedToolNames, contains('file_search_app_files'));
    expect(route.requiredToolNames, ['project_create_web_app']);
    expect(route.index, contains('project_create_web_app'));
  });

  test(
    'route asks model with latest prompt and recent context separately',
    () async {
      final chatClient = _RoutingChatClient(
        jsonEncode({
          'selected_tool_names': ['location_get_current', 'web_search'],
          'required_tool_names': <String>[],
          'uses_context': true,
          'reason': 'follow-up asks agent to execute previous weather plan',
        }),
      );

      final route = await router.route(
        prompt: '你自己做',
        context: 'assistant: 我可以先读取你当前位置，再搜索天气信息。',
        allTools: tools,
        chatClient: chatClient,
        provider: ModelProviders.aliyunBailianQwenFlash,
        apiKey: 'test-key',
      );

      expect(
        route.selectedToolNames,
        containsAll(['location_get_current', 'web_search']),
      );
      expect(chatClient.lastMessages.last['content'], isA<String>());
      final payload =
          jsonDecode(chatClient.lastMessages.last['content']! as String)
              as Map<String, Object?>;
      expect(payload['latest_user_message'], '你自己做');
      expect(payload['recent_context'], contains('天气信息'));
    },
  );

  test('web app maintenance exposes log and project file tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': ['artifact_query'],
        'required_tool_names': <String>[],
        'uses_context': true,
        'reason': 'model only selected artifact lookup',
      }),
    );

    final route = await router.route(
      prompt: '刚才那个预览页面打开是空白的，帮我修一下',
      context: 'assistant: 已创建 Web App Artifact，入口文件在 memo-app/index.html。',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'artifact_query',
        'artifact_inspect_logs',
        'file_search_app_files',
        'file_read_app_file',
        'project_update_web_app',
        'project_version_history',
        'project_revert_web_app',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
    expect(route.index, contains('project_update_web_app'));
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
