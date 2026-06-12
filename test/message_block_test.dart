import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/conversation/message_block.dart';

void main() {
  test('serializes and restores nested task progress blocks', () {
    final block = MessageBlock(
      type: MessageBlockType.taskProgress,
      data: {
        'status': 'completed',
        'blocks': [
          MessageBlock.toolCall('project_create_web_app', const {
            'title': '待办 Web App',
          }),
          MessageBlock.toolResult('project.create_web_app', const {
            'ok': true,
            'artifactId': 'artifact-todo',
            'summary': '已创建待办 Web App。',
          }),
        ],
      },
    );

    final decoded = jsonDecode(jsonEncode(block.toJson()));
    final restored = MessageBlock.fromJson(decoded);
    final nested = restored.data['blocks']! as List<Object?>;

    expect(restored.type, MessageBlockType.taskProgress);
    expect(nested, hasLength(2));
    expect(nested.first, isA<MessageBlock>());
    expect((nested.first! as MessageBlock).type, MessageBlockType.toolCall);
    expect(
      (nested.last! as MessageBlock).data['capabilityId'],
      'project.create_web_app',
    );
  });

  test('does not coerce ordinary tool output maps that look like blocks', () {
    final block = MessageBlock.toolResult('artifact.inspect', const {
      'ok': true,
      'payload': {
        'type': 'webAppCard',
        'data': {'title': '这只是工具数据'},
      },
    });

    final decoded = jsonDecode(jsonEncode(block.toJson()));
    final restored = MessageBlock.fromJson(decoded);
    final output = restored.data['output']! as Map<String, Object?>;
    final payload = output['payload'];

    expect(payload, isA<Map<String, Object?>>());
    expect(payload, isNot(isA<MessageBlock>()));
    expect((payload! as Map<String, Object?>)['type'], 'webAppCard');
  });
}
