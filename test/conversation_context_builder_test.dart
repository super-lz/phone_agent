import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/agent/conversation_context_builder.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';

void main() {
  test('keeps recent conversation entries verbatim', () {
    final context = const ConversationContextBuilder(maxRecentChars: 1000)
        .build([
          AgentMessage(
            id: 'user-1',
            role: MessageRole.user,
            createdAt: DateTime(2026),
            blocks: [MessageBlock.markdown('我叫张三')],
          ),
          AgentMessage(
            id: 'assistant-1',
            role: MessageRole.assistant,
            createdAt: DateTime(2026),
            blocks: [MessageBlock.markdown('你好，张三。')],
          ),
        ]);

    expect(context.summary, isEmpty);
    expect(context.recentEntries.map((entry) => entry.content), [
      '我叫张三',
      '你好，张三。',
    ]);
  });

  test('compacts older entries when recent context budget is full', () {
    final messages = List.generate(8, (index) {
      return AgentMessage(
        id: 'msg-$index',
        role: index.isEven ? MessageRole.user : MessageRole.assistant,
        createdAt: DateTime(2026),
        blocks: [MessageBlock.markdown('第 $index 条消息 ${'内容' * 20}')],
      );
    });

    final context = const ConversationContextBuilder(
      maxRecentChars: 90,
      maxSummaryChars: 300,
    ).build(messages);

    expect(context.summary, contains('第 0 条消息'));
    expect(context.recentEntries.last.content, contains('第 7 条消息'));
    expect(context.summary.length, lessThanOrEqualTo(303));
  });
}
