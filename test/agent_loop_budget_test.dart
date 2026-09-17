import 'package:flutter_test/flutter_test.dart';

import 'package:phone_agent/application/agent/agent_loop_budget.dart';

void main() {
  test('default run delegates completion to the model', () {
    const budget = AgentLoopBudget();
    final state = AgentLoopRunState(budget);

    expect(budget.maxModelRounds, isNull);
    expect(budget.maxToolCalls, isNull);
    expect(budget.maxConsecutiveToolFailures, isNull);
    expect(budget.maxConsecutiveNoProgress, isNull);

    for (var i = 0; i < 128; i += 1) {
      state.recordToolResult(false);
      state.recordProgress(false);
    }

    expect(state.canUseTools, isTrue);
    expect(state.stopReason, isEmpty);
  });

  test('explicit budgets remain available as optional circuit breakers', () {
    final state = AgentLoopRunState(
      const AgentLoopBudget(
        maxModelRounds: 3,
        maxToolCalls: 10,
        maxConsecutiveToolFailures: 2,
        maxConsecutiveNoProgress: 2,
      ),
    );

    state.recordToolResult(true);
    state.recordProgress(true);
    expect(state.canStartToolCall, isTrue);

    state.recordToolResult(false);
    state.recordProgress(false);
    state.recordToolResult(false);
    state.recordProgress(false);
    expect(state.canStartToolCall, isFalse);
    expect(state.stopReason, contains('连续 2'));
  });
}
