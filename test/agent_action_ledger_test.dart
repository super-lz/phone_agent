import 'package:flutter_test/flutter_test.dart';

import 'package:phone_agent/application/agent/agent_action_ledger.dart';
import 'package:phone_agent/application/capabilities/capability_execution_result.dart';
import 'package:phone_agent/application/capabilities/capability_runtime.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/memory/memory.dart';

void main() {
  test('canonical arguments make reordered duplicate calls replayable', () {
    final ledger = AgentActionLedger();
    final first = ledger.begin(
      toolCall: const ToolCallRequest(
        id: 'call-1',
        name: 'db_note_create',
        arguments: {'content': 'same', 'title': 'title'},
      ),
      capabilityId: 'db.note.create',
    );
    final completed = const CapabilityExecutionResult(
      capabilityId: 'db.note.create',
      output: {'ok': true, 'noteId': 'note-1'},
    ).withReceipt(actionId: first.record.actionId, argumentsHash: 'hash');
    ledger.complete(first.record, completed);

    final second = ledger.begin(
      toolCall: const ToolCallRequest(
        id: 'call-2',
        name: 'db_note_create',
        arguments: {'title': 'title', 'content': 'same'},
      ),
      capabilityId: 'db.note.create',
    );

    expect(second.isReplay, isTrue);
    expect(second.record.actionId, first.record.actionId);
  });

  test('explicit action ids allow two intentional identical actions', () {
    final ledger = AgentActionLedger();
    final first = ledger.begin(
      toolCall: const ToolCallRequest(
        id: 'call-1',
        name: 'db_note_create',
        arguments: {'content': 'same', '_agentActionId': 'action-a'},
      ),
      capabilityId: 'db.note.create',
    );
    ledger.complete(
      first.record,
      const CapabilityExecutionResult(
        capabilityId: 'db.note.create',
        output: {'ok': true},
      ),
    );

    final second = ledger.begin(
      toolCall: const ToolCallRequest(
        id: 'call-2',
        name: 'db_note_create',
        arguments: {'content': 'same', '_agentActionId': 'action-b'},
      ),
      capabilityId: 'db.note.create',
    );

    expect(second.isReplay, isFalse);
    expect(second.record.actionId, 'action-b');
  });

  test(
    'capability runtime executes an identical side effect only once',
    () async {
      final runtime = CapabilityRuntime();
      final ledger = AgentActionLedger();
      final memories = <AgentMemory>[];
      final context = AgentExecutionContext(
        runId: 'run-test',
        round: 0,
        ledger: ledger,
      );

      final first = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-1',
          name: 'memory_create',
          arguments: {'content': '只创建一次'},
        ),
        workspaceId: 'default',
        memories: memories,
        notes: const [],
        artifacts: const [],
        executionContext: context,
      );
      final second = await runtime.execute(
        toolCall: const ToolCallRequest(
          id: 'call-2',
          name: 'memory_create',
          arguments: {'content': '只创建一次'},
        ),
        workspaceId: 'default',
        memories: memories,
        notes: const [],
        artifacts: const [],
        executionContext: AgentExecutionContext(
          runId: 'run-test',
          round: 1,
          ledger: ledger,
        ),
      );

      expect(first.output['ok'], isTrue);
      expect(second.output['ok'], isTrue);
      expect(memories, hasLength(1));
      expect((second.output['receipt']! as Map)['replayed'], isTrue);
      expect(
        (second.output['receipt']! as Map)['actionId'],
        (first.output['receipt']! as Map)['actionId'],
      );
    },
  );
}
