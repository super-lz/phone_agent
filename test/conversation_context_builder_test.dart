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

  test('keeps todo list restored from json in transcript context', () {
    final restoredItems = <dynamic>['补齐本地会话', '切换工作区'];
    final context = const ConversationContextBuilder(maxRecentChars: 1000)
        .build([
          AgentMessage(
            id: 'assistant-todo',
            role: MessageRole.assistant,
            createdAt: DateTime(2026),
            blocks: [
              MessageBlock(
                type: MessageBlockType.todoList,
                data: {'items': restoredItems},
              ),
            ],
          ),
        ]);

    expect(context.recentEntries.single.content, contains('- 补齐本地会话'));
    expect(context.recentEntries.single.content, contains('- 切换工作区'));
  });

  test('summarizes tool results without leaking raw metadata', () {
    final context = const ConversationContextBuilder(maxRecentChars: 1000)
        .build([
          AgentMessage(
            id: 'assistant-tool',
            role: MessageRole.assistant,
            createdAt: DateTime(2026),
            blocks: [
              MessageBlock.toolCall('location_get_current', const {}),
              MessageBlock.toolResult('location.get_current', const {
                'ok': true,
                'summary': '当前位置：纬度 31.298900，经度 120.585300，精度约 30 米。',
                'latitude': 31.2989,
                'longitude': 120.5853,
                'hiddenRaw': '不应该进入模型历史',
              }),
            ],
          ),
        ]);

    final content = context.recentEntries.single.content;
    expect(content, contains('工具调用 location_get_current'));
    expect(content, contains('当前位置：纬度 31.298900'));
    expect(content, isNot(contains('hiddenRaw')));
    expect(content, isNot(contains('不应该进入模型历史')));
  });

  test('drops nested process block data from transcript context', () {
    final context = const ConversationContextBuilder(maxRecentChars: 1000)
        .build([
          AgentMessage(
            id: 'assistant-process',
            role: MessageRole.assistant,
            createdAt: DateTime(2026),
            blocks: [
              MessageBlock(
                type: MessageBlockType.taskProgress,
                data: {
                  'blocks': [
                    MessageBlock.toolResult('device.info', const {
                      'ok': true,
                      'rawDevice': {'brand': '不应该进入历史'},
                    }),
                  ],
                },
              ),
              MessageBlock.markdown('你的手机信息已经读取完成。'),
            ],
          ),
        ]);

    expect(context.recentEntries.single.content, '你的手机信息已经读取完成。');
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
