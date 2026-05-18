enum AgentRunPhase {
  routing,
  modelStreaming,
  waitingForToolCall,
  executingTool,
  waitingForeground,
  finalizing,
  completed,
  cancelled,
  failed,
}

class AgentRunSnapshot {
  const AgentRunSnapshot({
    required this.phase,
    required this.detail,
    required this.toolCallsUsed,
    required this.maxToolCalls,
    required this.startedAt,
    this.currentToolName,
  });

  final AgentRunPhase phase;
  final String detail;
  final int toolCallsUsed;
  final int maxToolCalls;
  final DateTime startedAt;
  final String? currentToolName;

  bool get isActive {
    return switch (phase) {
      AgentRunPhase.completed ||
      AgentRunPhase.cancelled ||
      AgentRunPhase.failed => false,
      _ => true,
    };
  }

  String get phaseLabel {
    return switch (phase) {
      AgentRunPhase.routing => '规划工具',
      AgentRunPhase.modelStreaming => '模型响应',
      AgentRunPhase.waitingForToolCall => '等待工具调用',
      AgentRunPhase.executingTool => '执行工具',
      AgentRunPhase.waitingForeground => '等待前台',
      AgentRunPhase.finalizing => '整理回答',
      AgentRunPhase.completed => '已完成',
      AgentRunPhase.cancelled => '已停止',
      AgentRunPhase.failed => '已失败',
    };
  }
}

class AgentRunControl {
  AgentRunControl();

  bool _isCancelled = false;
  String _reason = '用户已停止本轮任务。';

  bool get isCancelled => _isCancelled;
  String get reason => _reason;

  void cancel([String? reason]) {
    _isCancelled = true;
    if (reason != null && reason.trim().isNotEmpty) {
      _reason = reason.trim();
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw AgentRunCancelledException(_reason);
    }
  }
}

class AgentRunCancelledException implements Exception {
  const AgentRunCancelledException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
