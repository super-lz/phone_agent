import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/features/workbench/widgets/message_view.dart';
import 'package:phone_agent/features/workbench/widgets/tool_result_view.dart';

void main() {
  testWidgets('renders todo list restored from json without type crash', (
    tester,
  ) async {
    final restoredItems = <dynamic>['补齐本地会话', '切换工作区'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: MessageBlock(
              type: MessageBlockType.todoList,
              data: {'items': restoredItems},
            ),
          ),
        ),
      ),
    );

    expect(find.text('补齐本地会话'), findsOneWidget);
    expect(find.text('切换工作区'), findsOneWidget);
  });

  testWidgets('renders local attachments as readable cards', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MessageBlockView(
                onOpenWebAppArtifact: (_) {},
                block: MessageBlock.image(
                  name: '截图.png',
                  uri: 'file:///tmp/screenshot.png',
                  bytes: 4096,
                  mimeType: 'image/png',
                ),
              ),
              MessageBlockView(
                onOpenWebAppArtifact: (_) {},
                block: MessageBlock.fileAttachment(
                  name: '需求.md',
                  uri: 'file:///tmp/requirements.md',
                  bytes: 2048,
                  extension: 'md',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('截图.png'), findsOneWidget);
    expect(find.textContaining('image/png'), findsOneWidget);
    expect(find.text('需求.md'), findsOneWidget);
    expect(find.textContaining('file:///tmp/requirements.md'), findsOneWidget);
  });

  testWidgets('renders web search result as readable card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: const MessageBlock(
              type: MessageBlockType.toolResult,
              data: {
                'capabilityId': 'web.search',
                'output': {
                  'ok': true,
                  'provider': 'aliyun_bailian_websearch_mcp',
                  'query': 'AI 新闻',
                  'content': '搜索摘要\nhttps://example.com/news',
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('联网搜索结果'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.textContaining('aliyun_bailian_websearch_mcp'), findsOneWidget);
    expect(find.textContaining('搜索摘要'), findsOneWidget);
    expect(find.textContaining('https://example.com/news'), findsWidgets);
  });

  testWidgets('renders web tool error clearly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: const MessageBlock(
              type: MessageBlockType.toolResult,
              data: {
                'capabilityId': 'web.fetch',
                'output': {
                  'ok': false,
                  'provider': 'aliyun_bailian_websearch_mcp',
                  'url': 'https://example.com',
                  'error': 'HTTP 500',
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('网页解析结果'), findsOneWidget);
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('HTTP 500'), findsOneWidget);
  });

  testWidgets('shows generic tool summary and hides debug detail', (
    tester,
  ) async {
    const hiddenTail = '末尾诊断内容';
    final output = {
      'ok': true,
      'summary': '查询到了 1 条备忘。',
      'payload': '${'很长的工具输出 ' * 20}$hiddenTail',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: MessageBlock.toolResult('db.note.query', output),
          ),
        ),
      ),
    );

    expect(find.text('备忘查询'), findsOneWidget);
    expect(find.text('查询到了 1 条备忘。'), findsOneWidget);
    expect(find.textContaining(hiddenTail), findsNothing);

    await tester.tap(find.text('备忘查询'));
    await tester.pumpAndSettle();

    expect(find.textContaining(hiddenTail), findsOneWidget);
  });

  testWidgets('collapses assistant execution process by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            onOpenWebAppArtifact: (_) {},
            message: AgentMessage(
              id: 'assistant-process',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [
                MessageBlock.markdown('我先查询一下。'),
                MessageBlock.toolCall('web_search', {'query': '天气'}),
                MessageBlock.toolResult('web.search', const {
                  'ok': true,
                  'provider': 'test',
                  'query': '天气',
                  'content': '搜索结果正文',
                }),
                MessageBlock.markdown('最终回答。'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('已完成 联网搜索'), findsOneWidget);
    expect(find.text('最终回答。'), findsOneWidget);
    expect(find.text('我先查询一下。'), findsNothing);
    expect(find.text('联网搜索结果'), findsNothing);

    await tester.tap(find.text('已完成 联网搜索'));
    await tester.pumpAndSettle();

    expect(find.text('我先查询一下。'), findsOneWidget);
    expect(find.text('联网搜索结果'), findsOneWidget);
  });

  testWidgets('shows streaming tool preparation as expanded process', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            onOpenWebAppArtifact: (_) {},
            message: AgentMessage(
              id: 'assistant-preparing-tool',
              role: MessageRole.assistant,
              createdAt: DateTime(2026),
              blocks: [
                MessageBlock.intermediateMarkdown('''
先写入口页面：

```html
<html>
<body>正在生成的网页代码</body>
</html>
```
'''),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在思考...'), findsOneWidget);
    expect(find.textContaining('正在生成的网页代码'), findsNothing);
    expect(find.text('代码已折叠，点击展开查看。'), findsOneWidget);
  });

  testWidgets('tool process expands while running and collapses after result', (
    tester,
  ) async {
    final message = AgentMessage(
      id: 'assistant-tool-process',
      role: MessageRole.assistant,
      createdAt: DateTime(2026),
      blocks: [
        MessageBlock.toolCall('project_create_web_app', const {'title': '待办'}),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(onOpenWebAppArtifact: (_) {}, message: message),
        ),
      ),
    );

    expect(find.text('正在执行 创建 Web App'), findsOneWidget);
    expect(find.textContaining('Tool Call'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            onOpenWebAppArtifact: (_) {},
            message: AgentMessage(
              id: message.id,
              role: MessageRole.assistant,
              createdAt: message.createdAt,
              blocks: [
                ...message.blocks,
                MessageBlock.toolResult('project.create_web_app', const {
                  'ok': true,
                  'summary': '已创建待办 Web App',
                }),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('已完成 创建 Web App'), findsOneWidget);
    expect(find.textContaining('Tool Call'), findsNothing);
  });

  testWidgets('collapses long code blocks until expanded', (tester) async {
    final code = List.generate(
      20,
      (index) => 'final value$index = $index;',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: MessageBlock.code('dart', code),
          ),
        ),
      ),
    );

    expect(find.text('dart'), findsOneWidget);
    expect(find.textContaining('value19'), findsNothing);

    await tester.tap(find.text('dart'));
    await tester.pumpAndSettle();

    expect(find.textContaining('value19'), findsOneWidget);
  });

  testWidgets('collapses fenced markdown code during streaming', (
    tester,
  ) async {
    final repeatedScript = List.filled(40, 'const value = 1;').join('\n');
    final html =
        '''
我正在创建页面：

```html
<!doctype html>
<html>
<body>
<script>
$repeatedScript
</script>
</body>
</html>
```
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageBlockView(
              onOpenWebAppArtifact: (_) {},
              block: MessageBlock.markdown(html),
            ),
          ),
        ),
      ),
    );

    expect(find.text('html'), findsOneWidget);
    expect(find.text('代码已折叠，点击展开查看。'), findsOneWidget);
    expect(find.textContaining('<!doctype html>'), findsNothing);

    await tester.tap(find.text('html'));
    await tester.pumpAndSettle();

    expect(find.textContaining('<!doctype html>'), findsOneWidget);
  });

  testWidgets('repairs unmatched bold markers in markdown output', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (_) {},
            block: MessageBlock.markdown('这是 **关键结论'),
          ),
        ),
      ),
    );

    expect(find.textContaining('关键结论'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('renders web app artifact as a preview card', (tester) async {
    var openedArtifactId = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            onOpenWebAppArtifact: (artifactId) {
              openedArtifactId = artifactId;
            },
            block: MessageBlock.webAppCard('artifact-webapp-1', '美食网页'),
          ),
        ),
      ),
    );

    expect(find.text('美食网页'), findsOneWidget);
    expect(find.text('本地应用 · 点击预览'), findsOneWidget);

    await tester.tap(find.text('本地应用 · 点击预览'));
    await tester.pumpAndSettle();

    expect(openedArtifactId, 'artifact-webapp-1');
  });

  testWidgets('successful location result exposes map action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToolResultView(
            capabilityId: 'location.get_current',
            output: {
              'ok': true,
              'latitude': 31.2304,
              'longitude': 121.4737,
              'accuracy': 42.0,
              'address': '上海市黄浦区人民大道',
              'provider': 'amap_location',
              'coordinateSystem': 'gcj02',
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('当前位置：上海市黄浦区人民大道'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '查看地图'), findsOneWidget);
  });
}
