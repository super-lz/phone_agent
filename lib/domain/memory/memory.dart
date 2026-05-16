enum MemoryScope { global, workspace, session }

class AgentMemory {
  const AgentMemory({
    required this.id,
    required this.scope,
    required this.content,
    required this.createdAt,
    this.workspaceId,
  });

  final String id;
  final MemoryScope scope;
  final String content;
  final DateTime createdAt;
  final String? workspaceId;
}

extension MemoryScopeLabel on MemoryScope {
  String get label {
    switch (this) {
      case MemoryScope.global:
        return '全局';
      case MemoryScope.workspace:
        return '工作区';
      case MemoryScope.session:
        return '会话';
    }
  }
}
