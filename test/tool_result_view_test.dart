import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';
import 'package:phone_agent/features/workbench/widgets/message_view.dart';

void main() {
  testWidgets('renders web search result as readable card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            block: MessageBlock(
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
      const MaterialApp(
        home: Scaffold(
          body: MessageBlockView(
            block: MessageBlock(
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
}
