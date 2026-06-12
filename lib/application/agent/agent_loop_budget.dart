class AgentLoopBudget {
  const AgentLoopBudget({
    this.maxModelRounds = 32,
    this.maxToolCalls = 96,
    this.maxConsecutiveToolFailures = 4,
  });

  final int maxModelRounds;
  final int maxToolCalls;
  final int maxConsecutiveToolFailures;
}

class AgentLoopRunState {
  AgentLoopRunState(this.budget);

  final AgentLoopBudget budget;
  int toolCallsUsed = 0;
  int consecutiveToolFailures = 0;
  String stopReason = '';

  bool get canStartToolCall {
    return toolCallsUsed < budget.maxToolCalls &&
        consecutiveToolFailures < budget.maxConsecutiveToolFailures;
  }

  bool get canUseTools => canStartToolCall;

  void recordToolResult(bool ok) {
    toolCallsUsed += 1;
    if (ok) {
      consecutiveToolFailures = 0;
    } else {
      consecutiveToolFailures += 1;
    }
    if (toolCallsUsed >= budget.maxToolCalls) {
      stopReason = '已达到本轮对话的最大工具调用次数 ${budget.maxToolCalls} 次。';
      return;
    }
    if (consecutiveToolFailures >= budget.maxConsecutiveToolFailures) {
      stopReason = '连续 ${budget.maxConsecutiveToolFailures} 次工具调用失败，避免无效重试。';
    }
  }
}
