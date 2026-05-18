import '../artifacts/artifact.dart';
import '../capabilities/capability.dart';
import '../conversation/message_block.dart';
import '../memory/memory.dart';
import '../workspace/workspace.dart';

abstract class WorkbenchStore {
  Future<void> initialize({
    required List<AgentWorkspace> seedWorkspaces,
    required List<AgentMemory> seedMemories,
    required List<AgentArtifact> seedArtifacts,
    required List<AgentMessage> seedMessages,
    required String defaultWorkspaceId,
  });

  Future<List<AgentWorkspace>> loadWorkspaces();

  Future<String?> loadCurrentWorkspaceId();

  Future<void> saveCurrentWorkspaceId(String workspaceId);

  Future<void> upsertWorkspace(AgentWorkspace workspace);

  Future<List<AgentMemory>> loadMemories();

  Future<void> upsertMemory(AgentMemory memory);

  Future<void> deleteMemory(String memoryId);

  Future<List<AgentArtifact>> loadArtifacts();

  Future<void> upsertArtifact(AgentArtifact artifact);

  Future<List<AgentMessage>> loadMessages(String workspaceId);

  Future<void> upsertMessage({
    required String workspaceId,
    required AgentMessage message,
  });

  Future<void> recordInvocation(CapabilityInvocation invocation);

  Future<List<CapabilityInvocation>> loadInvocations();

  Future<void> resetLocalData({
    required AgentWorkspace defaultWorkspace,
    required List<AgentMessage> defaultMessages,
  });

  Future<void> close();
}

class InMemoryWorkbenchStore implements WorkbenchStore {
  final _workspaces = <String, AgentWorkspace>{};
  final _memories = <String, AgentMemory>{};
  final _artifacts = <String, AgentArtifact>{};
  final _messagesByWorkspace = <String, Map<String, AgentMessage>>{};
  final _invocations = <CapabilityInvocation>[];
  String? _currentWorkspaceId;

  @override
  Future<void> initialize({
    required List<AgentWorkspace> seedWorkspaces,
    required List<AgentMemory> seedMemories,
    required List<AgentArtifact> seedArtifacts,
    required List<AgentMessage> seedMessages,
    required String defaultWorkspaceId,
  }) async {
    _workspaces.addEntries(
      seedWorkspaces.map((workspace) => MapEntry(workspace.id, workspace)),
    );
    _memories.addEntries(
      seedMemories.map((memory) => MapEntry(memory.id, memory)),
    );
    _artifacts.addEntries(
      seedArtifacts.map((artifact) => MapEntry(artifact.id, artifact)),
    );
    _messagesByWorkspace.putIfAbsent(defaultWorkspaceId, () => {});
    final defaultMessages = _messagesByWorkspace[defaultWorkspaceId]!;
    for (final message in seedMessages) {
      defaultMessages.putIfAbsent(message.id, () => message);
    }
    _currentWorkspaceId ??= defaultWorkspaceId;
  }

  @override
  Future<List<AgentWorkspace>> loadWorkspaces() async {
    return _workspaces.values.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<String?> loadCurrentWorkspaceId() async => _currentWorkspaceId;

  @override
  Future<void> saveCurrentWorkspaceId(String workspaceId) async {
    _currentWorkspaceId = workspaceId;
  }

  @override
  Future<void> upsertWorkspace(AgentWorkspace workspace) async {
    _workspaces[workspace.id] = workspace;
  }

  @override
  Future<List<AgentMemory>> loadMemories() async {
    return _memories.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> upsertMemory(AgentMemory memory) async {
    _memories[memory.id] = memory;
  }

  @override
  Future<void> deleteMemory(String memoryId) async {
    _memories.remove(memoryId);
  }

  @override
  Future<List<AgentArtifact>> loadArtifacts() async {
    return _artifacts.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> upsertArtifact(AgentArtifact artifact) async {
    _artifacts[artifact.id] = artifact;
  }

  @override
  Future<List<AgentMessage>> loadMessages(String workspaceId) async {
    final messages = _messagesByWorkspace[workspaceId]?.values ?? const [];
    return messages.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> upsertMessage({
    required String workspaceId,
    required AgentMessage message,
  }) async {
    _messagesByWorkspace.putIfAbsent(workspaceId, () => {})[message.id] =
        message;
  }

  @override
  Future<void> recordInvocation(CapabilityInvocation invocation) async {
    _invocations.add(invocation);
  }

  @override
  Future<List<CapabilityInvocation>> loadInvocations() async {
    return List.unmodifiable(_invocations);
  }

  @override
  Future<void> resetLocalData({
    required AgentWorkspace defaultWorkspace,
    required List<AgentMessage> defaultMessages,
  }) async {
    _workspaces.clear();
    _workspaces[defaultWorkspace.id] = defaultWorkspace;
    _memories.clear();
    _artifacts.clear();
    _messagesByWorkspace.clear();
    _messagesByWorkspace[defaultWorkspace.id] = {
      for (final message in defaultMessages) message.id: message,
    };
    _invocations.clear();
    _currentWorkspaceId = defaultWorkspace.id;
  }

  @override
  Future<void> close() async {}
}
