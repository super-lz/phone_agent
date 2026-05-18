import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/features/workbench/widgets/message_view.dart';

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

  testWidgets('collapses verbose tool results until expanded', (tester) async {
    const hiddenTail = '末尾诊断内容';
    final output = {'ok': true, 'payload': '${'很长的工具输出 ' * 20}$hiddenTail'};

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

    expect(find.textContaining('Tool Result · db.note.query'), findsOneWidget);
    expect(find.textContaining(hiddenTail), findsNothing);

    await tester.tap(find.textContaining('Tool Result · db.note.query'));
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

    expect(find.text('已处理'), findsOneWidget);
    expect(find.textContaining('1 次调用'), findsOneWidget);
    expect(find.text('最终回答。'), findsOneWidget);
    expect(find.text('我先查询一下。'), findsNothing);
    expect(find.text('联网搜索结果'), findsNothing);

    await tester.tap(find.text('已处理'));
    await tester.pumpAndSettle();

    expect(find.text('我先查询一下。'), findsOneWidget);
    expect(find.text('联网搜索结果'), findsOneWidget);
  });

  testWidgets('shows streaming tool preparation as collapsed process', (
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

    expect(find.text('处理中'), findsOneWidget);
    expect(find.textContaining('正在生成的网页代码'), findsNothing);

    await tester.tap(find.text('处理中'));
    await tester.pumpAndSettle();

    expect(find.text('代码已折叠，点击展开查看。'), findsOneWidget);
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
}
