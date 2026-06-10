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
        'project_test_web_app',
        'project_version_history',
        'project_revert_web_app',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
    expect(route.index, contains('project_update_web_app'));
    expect(route.index, contains('project_test_web_app'));
  });

  test('web app creation exposes project test tool', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': ['project_create_web_app'],
        'required_tool_names': ['project_create_web_app'],
        'uses_context': false,
        'reason': 'create local web app',
      }),
    );

    final route = await router.route(
      prompt: '创建一个本地 Web App 记账页面',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll(['project_create_web_app', 'project_test_web_app']),
    );
    expect(route.requiredToolNames, contains('project_create_web_app'));
    expect(route.index, contains('project_test_web_app'));
  });

  test('native input requests expose system picker tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed native input tools',
      }),
    );

    final route = await router.route(
      prompt: '帮我拍照、拍视频，再从相册选图片和视频，还要选一个 PDF 文件，然后开始录音',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'camera_capture_photo',
        'camera_capture_video',
        'audio_record_start',
        'media_pick_image',
        'media_pick_video',
        'file_pick_system_file',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
  });

  test('native device status requests expose phone status tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed native status tools',
      }),
    );

    final route = await router.route(
      prompt: '看一下手机信息、当前电量、网络状态和现在几点',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'device_info',
        'battery_status',
        'network_status',
        'time_get_current',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
  });

  test('native control requests expose phone control tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed native control tools',
      }),
    );

    final route = await router.route(
      prompt:
          '把这段文字复制到剪贴板并调起系统分享，震动一下，播放提示音，进入全屏沉浸模式，保持屏幕常亮，把屏幕亮度调暗，锁定横屏并查看方向状态，再打开链接 https://example.com',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'clipboard_write',
        'share_text',
        'system_haptic_feedback',
        'system_sound_alert',
        'system_ui_set',
        'system_ui_status',
        'screen_keep_awake',
        'screen_brightness_set',
        'screen_brightness_status',
        'screen_orientation_set',
        'screen_orientation_status',
        'url_open_external',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
  });

  test('native sensor requests expose sensor snapshot tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed sensor tools',
      }),
    );

    final route = await router.route(
      prompt: '读取加速度计、陀螺仪和指南针数据',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'sensor_accelerometer_read',
        'sensor_gyroscope_read',
        'sensor_magnetometer_read',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
  });

  test('notification management requests expose notification tools', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed notification tools',
      }),
    );

    final route = await router.route(
      prompt: '帮我查看提醒列表，然后取消提醒，最后清空全部提醒',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(
      route.selectedToolNames,
      containsAll([
        'notification_pending',
        'notification_cancel',
        'notification_cancel_all',
      ]),
    );
    expect(route.requiredToolNames, isEmpty);
  });

  test('contact requests expose contact picker tool', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed contact picker',
      }),
    );

    final route = await router.route(
      prompt: '从通讯录选择联系人给这个 Web App 使用',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, contains('contacts_pick'));
    expect(route.requiredToolNames, isEmpty);
  });

  test('barcode scan requests expose camera scan tool', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed barcode scan',
      }),
    );

    final route = await router.route(
      prompt: '帮我扫描二维码',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, contains('barcode_scan_camera'));
    expect(route.requiredToolNames, isEmpty);
  });

  test('flashlight requests expose flashlight set tool', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed flashlight control',
      }),
    );

    final route = await router.route(
      prompt: '帮我打开手电筒',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, contains('flashlight_set'));
    expect(route.requiredToolNames, isEmpty);
  });

  test('multiple image requests expose multi image picker', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed multi image picker',
      }),
    );

    final route = await router.route(
      prompt: '从相册选择多张照片给我分析',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, contains('media_pick_images'));
    expect(route.selectedToolNames, isNot(contains('media_pick_image')));
    expect(route.requiredToolNames, isEmpty);
  });

  test('barcode image requests expose image scan tool', () async {
    final chatClient = _RoutingChatClient(
      jsonEncode({
        'selected_tool_names': <String>[],
        'required_tool_names': <String>[],
        'uses_context': false,
        'reason': 'model missed barcode image scan',
      }),
    );

    final route = await router.route(
      prompt: '识别这张截图里的二维码',
      context: '',
      allTools: tools,
      chatClient: chatClient,
      provider: ModelProviders.aliyunBailianQwenFlash,
      apiKey: 'test-key',
    );

    expect(route.selectedToolNames, contains('barcode_scan_image'));
    expect(route.requiredToolNames, isEmpty);
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
