class AgentLoopBudget {
  const AgentLoopBudget({
    this.maxModelRounds,
    this.maxToolCalls,
    this.maxConsecutiveToolFailures,
    this.maxConsecutiveNoProgress,
  });

  /// Null means the model decides when the run is complete.
  final int? maxModelRounds;

  /// Null means tools remain available until the model returns a final answer
  /// or an independent runtime boundary (cancellation, permission, context,
  /// or transport failure) ends the run.
  final int? maxToolCalls;

  /// Optional defensive circuit breakers for deployments that need them.
  final int? maxConsecutiveToolFailures;
  final int? maxConsecutiveNoProgress;
}

class AgentLoopRunState {
  AgentLoopRunState(this.budget);

  final AgentLoopBudget budget;
  int toolCallsUsed = 0;
  int consecutiveToolFailures = 0;
  int consecutiveNoProgress = 0;
  String stopReason = '';

  bool get canStartToolCall {
    final maxToolCalls = budget.maxToolCalls;
    final maxConsecutiveToolFailures = budget.maxConsecutiveToolFailures;
    final maxConsecutiveNoProgress = budget.maxConsecutiveNoProgress;
    return (maxToolCalls == null || toolCallsUsed < maxToolCalls) &&
        (maxConsecutiveToolFailures == null ||
            consecutiveToolFailures < maxConsecutiveToolFailures) &&
        (maxConsecutiveNoProgress == null ||
            consecutiveNoProgress < maxConsecutiveNoProgress);
  }

  bool get canUseTools => canStartToolCall;

  void recordToolResult(bool ok) {
    toolCallsUsed += 1;
    if (ok) {
      consecutiveToolFailures = 0;
    } else {
      consecutiveToolFailures += 1;
    }
    final maxToolCalls = budget.maxToolCalls;
    if (maxToolCalls != null && toolCallsUsed >= maxToolCalls) {
      stopReason = '已达到本轮对话的最大工具调用次数 $maxToolCalls 次。';
      return;
    }
    final maxConsecutiveToolFailures = budget.maxConsecutiveToolFailures;
    if (maxConsecutiveToolFailures != null &&
        consecutiveToolFailures >= maxConsecutiveToolFailures) {
      stopReason = '连续 $maxConsecutiveToolFailures 次工具调用失败，避免无效重试。';
    }
  }

  void recordProgress(bool progressed) {
    consecutiveNoProgress = progressed ? 0 : consecutiveNoProgress + 1;
    final maxConsecutiveNoProgress = budget.maxConsecutiveNoProgress;
    if (maxConsecutiveNoProgress != null &&
        consecutiveNoProgress >= maxConsecutiveNoProgress) {
      stopReason = '连续 $maxConsecutiveNoProgress 轮没有产生新动作，系统停止继续自动调用。';
    }
  }
}
