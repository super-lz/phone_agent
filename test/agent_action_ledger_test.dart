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

  test(
    'replaying one action does not block an independent later action',
    () async {
      final runtime = CapabilityRuntime();
      final ledger = AgentActionLedger();
      final memories = <AgentMemory>[];

      Future<void> execute(String callId, String content, int round) async {
        await runtime.execute(
          toolCall: ToolCallRequest(
            id: callId,
            name: 'memory_create',
            arguments: {'content': content},
          ),
          workspaceId: 'default',
          memories: memories,
          notes: const [],
          artifacts: const [],
          executionContext: AgentExecutionContext(
            runId: 'run-test',
            round: round,
            ledger: ledger,
          ),
        );
      }

      await execute('call-a', '动作 A', 0);
      await execute('call-a-replay', '动作 A', 1);
      await execute('call-b', '动作 B', 2);

      expect(memories.map((memory) => memory.content), ['动作 A', '动作 B']);
    },
  );

  test('an interrupted running action restores as result unknown', () {
    final original = AgentActionLedger();
    original.begin(
      toolCall: const ToolCallRequest(
        id: 'call-external-write',
        name: 'db_note_create',
        arguments: {'title': '中断写入', 'content': '不能盲目重试'},
      ),
      capabilityId: 'db.note.create',
    );

    final restored = AgentActionLedger.fromJson(original.toJson());
    final decision = restored.begin(
      toolCall: const ToolCallRequest(
        id: 'call-after-restart',
        name: 'db_note_create',
        arguments: {'title': '中断写入', 'content': '不能盲目重试'},
      ),
      capabilityId: 'db.note.create',
    );

    expect(decision.requiresResolution, isTrue);
    expect(decision.record.status, AgentActionStatus.resultUnknown);
  });

  test('unknown persisted ledger status is treated as result unknown', () {
    final restored = AgentActionLedger.fromJson([
      {
        'actionId': 'action-1',
        'callId': 'call-1',
        'capabilityId': 'memory.create',
        'fingerprint': 'memory.create:abc',
        'status': 'a_future_status',
        'deduplicate': true,
      },
    ]);

    expect(restored.records.single.status, AgentActionStatus.resultUnknown);
  });

  test('restored result unknown action is not executed again', () async {
    final original = AgentActionLedger();
    original.begin(
      toolCall: const ToolCallRequest(
        id: 'call-before-crash',
        name: 'memory_create',
        arguments: {'content': '不得重试'},
      ),
      capabilityId: 'memory.create',
    );
    final memories = <AgentMemory>[];
    final result = await CapabilityRuntime().execute(
      toolCall: const ToolCallRequest(
        id: 'call-after-restart',
        name: 'memory_create',
        arguments: {'content': '不得重试'},
      ),
      workspaceId: 'default',
      memories: memories,
      notes: const [],
      artifacts: const [],
      executionContext: AgentExecutionContext(
        runId: 'recovered-run',
        round: 0,
        ledger: AgentActionLedger.fromJson(original.toJson()),
      ),
    );

    expect(result.output['error'], 'action_result_unknown');
    expect((result.output['receipt']! as Map)['status'], 'result_unknown');
    expect(memories, isEmpty);
  });
}
