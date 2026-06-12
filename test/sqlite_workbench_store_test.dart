import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/workbench/sqlite_workbench_store.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';

void main() {
  test('recovers valid message blocks when one persisted block is corrupt', () {
    final store = SqliteWorkbenchStore.forPath('/unused.sqlite');
    final blocksJson = jsonEncode(<Map<String, Object?>>[
      MessageBlock.markdown('已创建待办 Web App。').toJson(),
      {'type': 'notARealBlock', 'data': <String, Object?>{}},
      MessageBlock.webAppCard('artifact-1', '待办 Web App').toJson(),
    ]);

    final blocks = store.decodeMessageBlocksForTesting(
      messageId: 'message-1',
      blocksJson: blocksJson,
    );

    expect(blocks, hasLength(3));
    expect(blocks[0].type, MessageBlockType.markdownText);
    expect(blocks[1].type, MessageBlockType.webAppCard);
    expect(blocks[2].type, MessageBlockType.errorCard);
    expect(blocks[2].data['title'], '部分消息内容不可读');
  });

  test('uses an error block when persisted blocks json is unreadable', () {
    final store = SqliteWorkbenchStore.forPath('/unused.sqlite');

    final blocks = store.decodeMessageBlocksForTesting(
      messageId: 'message-2',
      blocksJson: '{not valid json',
    );

    expect(blocks, hasLength(1));
    expect(blocks.single.type, MessageBlockType.errorCard);
    expect(blocks.single.data['title'], '消息内容不可读');
  });

  test(
    'uses an error message when persisted message row metadata is corrupt',
    () {
      final store = SqliteWorkbenchStore.forPath('/unused.sqlite');

      final message = store.decodeMessageForTesting({
        'id': 'message-3',
        'role': 'not_a_role',
        'created_at': 'not a date',
        'blocks_json': jsonEncode([
          MessageBlock.markdown('这段内容不会被当成完整消息恢复。').toJson(),
        ]),
      });

      expect(message.id, 'message-3');
      expect(message.role, MessageRole.assistant);
      expect(message.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(message.blocks, hasLength(1));
      expect(message.blocks.single.type, MessageBlockType.errorCard);
      expect(message.blocks.single.data['title'], '消息记录不可读');
    },
  );
}
