import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/tool_router.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';

void main() {
  final tools = CapabilityRuntime().toolDefinitions;
  const router = AgentToolRouter();

  test('ordinary chat does not expose full tool catalog', () {
    final route = router.route(prompt: '你好，随便聊聊', allTools: tools);

    expect(route.tools, isEmpty);
    expect(route.index, contains('未暴露工具 schema'));
  });

  test('web search intent exposes search and fetch tools only', () {
    final route = router.route(prompt: '帮我搜索 Flutter 最新信息', allTools: tools);

    expect(route.selectedToolNames, containsAll(['web_search', 'web_fetch']));
    expect(route.selectedToolNames, isNot(contains('device_info')));
    expect(route.tools.length, lessThan(tools.length));
  });

  test('web app intent exposes project and maintenance tools', () {
    final route = router.route(
      prompt: '创建一个可以预览的美食网页，并能后续修复 bug',
      allTools: tools,
    );

    expect(route.selectedToolNames, contains('project_create_web_app'));
    expect(route.selectedToolNames, contains('file_search_app_files'));
    expect(route.selectedToolNames, contains('file_read_app_file'));
    expect(route.selectedToolNames, contains('file_apply_text_patch'));
    expect(route.selectedToolNames, contains('artifact_create'));
  });

  test('create app intent routes to local web project tools', () {
    final route = router.route(prompt: '帮我创建一个备忘录应用', allTools: tools);

    expect(route.selectedToolNames, contains('project_create_web_app'));
    expect(route.selectedToolNames, contains('artifact_create'));
  });

  test('phone capability intent exposes matching native tools', () {
    final route = router.route(prompt: '看下我的手机信息和当前位置', allTools: tools);

    expect(route.selectedToolNames, contains('device_info'));
    expect(route.selectedToolNames, contains('location_get_current'));
    expect(route.selectedToolNames, isNot(contains('web_search')));
  });

  test(
    'office intent exposes document spreadsheet presentation and pdf tools',
    () {
      final route = router.route(
        prompt: '帮我总结这个 Word 和生成一个 PPT/PDF',
        allTools: tools,
      );

      expect(route.selectedToolNames, contains('document_extract'));
      expect(route.selectedToolNames, contains('presentation_generate'));
      expect(route.selectedToolNames, contains('pdf_generate'));
    },
  );
}
