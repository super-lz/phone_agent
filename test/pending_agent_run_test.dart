import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/domain/workbench/pending_agent_run.dart';

void main() {
  test('round-trips the versioned action checkpoint', () {
    final run = PendingAgentRun(
      id: 'run-1',
      workspaceId: 'default',
      userPrompt: '保存一条记录',
      modelPrompt: '保存一条记录',
      priorMessages: const [],
      startedAt: DateTime.utc(2026, 9, 18),
      actionLedgerVersion: 1,
      actionLedger: const [
        {
          'actionId': 'action-1',
          'callId': 'call-1',
          'capabilityId': 'memory.create',
          'fingerprint': 'memory.create:abc',
          'status': 'completed',
          'deduplicate': true,
        },
      ],
    );

    final restored = PendingAgentRun.fromJson(run.toJson());

    expect(restored.actionLedgerVersion, 1);
    expect(restored.actionLedger, run.actionLedger);
  });

  test('legacy records without a checkpoint version remain readable', () {
    final restored = PendingAgentRun.fromJson({
      'id': 'legacy-run',
      'workspaceId': 'default',
      'userPrompt': '旧任务',
      'modelPrompt': '旧任务',
      'priorMessages': const [],
      'startedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
    });

    expect(restored.actionLedgerVersion, 0);
    expect(restored.actionLedger, isEmpty);
    expect(restored.protocolVersion, 0);
    expect(restored.modelMessages, isEmpty);
  });

  test('round-trips model protocol separately from display history', () {
    final run = PendingAgentRun(
      id: 'run-protocol',
      workspaceId: 'default',
      userPrompt: '保存笔记',
      modelPrompt: '保存笔记',
      priorMessages: const [],
      startedAt: DateTime.utc(2026, 9, 18),
      modelStep: 3,
      toolIndex: '已选工具：db_note_create',
      toolSchema: const [
        {
          'type': 'function',
          'function': {'name': 'db_note_create'},
        },
      ],
      modelMessages: const [
        {'role': 'user', 'content': '保存笔记'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call-1',
              'type': 'function',
              'function': {'name': 'db_note_create', 'arguments': '{}'},
            },
          ],
        },
      ],
    );

    final restored = PendingAgentRun.fromJson(run.toJson());

    expect(restored.protocolVersion, 1);
    expect(restored.modelStep, 3);
    expect(restored.toolIndex, contains('db_note_create'));
    expect(restored.toolSchema.single['function'], isA<Map>());
    expect(restored.modelMessages.last['tool_calls'], isA<List>());
  });
}
