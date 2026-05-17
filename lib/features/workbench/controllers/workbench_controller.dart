import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../application/agent/agent_loop.dart';
import '../../../application/capabilities/capability_runtime.dart';
import '../../../core/logging/app_logger.dart';
import '../../../data/bootstrap/phone_agent_seed.dart';
import '../../../data/models/model_api_key_store.dart';
import '../../../data/models/openai_compatible_chat_client.dart';
import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/conversation/message_block.dart';
import '../../../domain/files/app_file_store.dart';
import '../../../domain/memory/memory.dart';
import '../../../domain/models/model_provider_config.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/notes/note_store.dart';
import '../../../domain/permissions/permission_policy.dart';
import '../../../domain/workspace/workspace.dart';
import '../../web_app_runtime/web_app_capability_bridge.dart';

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    ModelApiKeyStore? apiKeyStore,
    OpenAiCompatibleChatClient? chatClient,
    CapabilityRuntime? capabilityRuntime,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
  }) : this._(
         apiKeyStore: apiKeyStore ?? ModelApiKeyStore(),
         chatClient: chatClient ?? OpenAiCompatibleChatClient(),
         capabilityRuntime: capabilityRuntime ?? CapabilityRuntime(),
         noteStore: noteStore ?? InMemoryAgentNoteStore(PhoneAgentSeed.notes()),
         fileStore: fileStore ?? InMemoryAppFileStore(),
       );

  WorkbenchController._({
    required ModelApiKeyStore apiKeyStore,
    required OpenAiCompatibleChatClient chatClient,
    required CapabilityRuntime capabilityRuntime,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
  }) : _apiKeyStore = apiKeyStore,
       _agentLoop = AgentLoop(
         chatClient: chatClient,
         capabilityRuntime: capabilityRuntime,
       ),
       _webAppBridge = WebAppCapabilityBridge(
         capabilityRuntime: capabilityRuntime,
         apiKeyStore: apiKeyStore,
         noteStore: noteStore,
         fileStore: fileStore,
       ),
       _noteStore = noteStore,
       _fileStore = fileStore,
       _workspaces = PhoneAgentSeed.workspaces(),
       _capabilities = PhoneAgentSeed.capabilities(),
       _messages = PhoneAgentSeed.messages(),
       _memories = PhoneAgentSeed.memories(),
       _artifacts = PhoneAgentSeed.artifacts(),
       _notes = PhoneAgentSeed.notes() {
    unawaited(_loadNotes());
  }

  final ModelApiKeyStore _apiKeyStore;
  final AgentLoop _agentLoop;
  final WebAppCapabilityBridge _webAppBridge;
  final AgentNoteStore _noteStore;
  final AppFileStore _fileStore;
  final List<AgentWorkspace> _workspaces;
  final List<CapabilityDefinition> _capabilities;
  final List<AgentMessage> _messages;
  final List<AgentMemory> _memories;
  final List<AgentArtifact> _artifacts;
  final List<AgentNote> _notes;

  PermissionMode _permissionMode = PermissionMode.defaultMode;
  String _workspaceId = 'default';
  bool _isSending = false;
  bool _isDisposed = false;

  List<AgentWorkspace> get workspaces => List.unmodifiable(_workspaces);
  List<CapabilityDefinition> get capabilities =>
      List.unmodifiable(_capabilities);
  List<AgentMessage> get messages => List.unmodifiable(_messages);
  List<AgentMemory> get visibleMemories {
    return List.unmodifiable(_memories);
  }

  List<AgentArtifact> get workspaceArtifacts {
    return _artifacts
        .where((artifact) => artifact.workspaceId == _workspaceId)
        .toList(growable: false);
  }

  List<AgentNote> get workspaceNotes {
    return _notes
        .where((note) => note.workspaceId == _workspaceId)
        .toList(growable: false);
  }

  AgentArtifact? artifactById(String artifactId) {
    for (final artifact in _artifacts) {
      if (artifact.id == artifactId) {
        return artifact;
      }
    }
    return null;
  }

  List<PermissionMode> get permissionModes => PermissionMode.values;
  PermissionMode get permissionMode => _permissionMode;
  String get workspaceId => _workspaceId;
  bool get isSending => _isSending;

  AgentWorkspace get currentWorkspace {
    return _workspaces.firstWhere((workspace) => workspace.id == _workspaceId);
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_noteStore.close());
    super.dispose();
  }

  Future<void> _loadNotes() async {
    try {
      final loadedNotes = await _noteStore.loadAll();
      final mergedById = {
        for (final note in loadedNotes) note.id: note,
        for (final note in _notes) note.id: note,
      };
      _notes
        ..clear()
        ..addAll(mergedById.values);
      AppLogger.info('workbench.notes.loaded', {'count': _notes.length});
      if (!_isDisposed) {
        notifyListeners();
      }
    } on Object catch (error) {
      AppLogger.warning('workbench.notes.load_failed', {
        'error': error.toString(),
      });
    }
  }

  void setPermissionMode(PermissionMode? mode) {
    if (mode == null || mode == _permissionMode) {
      return;
    }
    _permissionMode = mode;
    notifyListeners();
  }

  void setWorkspace(String workspaceId) {
    if (workspaceId == _workspaceId) {
      return;
    }
    _workspaceId = workspaceId;
    notifyListeners();
  }

  void createWorkspace() {
    final next = _workspaces.length + 1;
    final workspace = AgentWorkspace(
      id: 'workspace-$next',
      name: '新工作区 $next',
      description: '用于区分一组会话、文件、Artifact 和任务数据。',
      createdAt: DateTime.now(),
    );
    _workspaces.add(workspace);
    _workspaceId = workspace.id;
    _messages.add(
      AgentMessage(
        id: 'msg-workspace-$next',
        role: MessageRole.system,
        createdAt: DateTime.now(),
        blocks: [MessageBlock.markdown('已创建并切换到 **${workspace.name}**。')],
      ),
    );
    notifyListeners();
  }

  void createMemory({required String content}) {
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return;
    }

    final memory = AgentMemory(
      id: 'memory-${DateTime.now().microsecondsSinceEpoch}',
      content: normalized,
      createdAt: DateTime.now(),
    );
    _memories.add(memory);
    AppLogger.info('workbench.memory.create', {'memoryId': memory.id});
    notifyListeners();
  }

  void updateMemory({required String memoryId, required String content}) {
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return;
    }

    final index = _memories.indexWhere((memory) => memory.id == memoryId);
    if (index < 0) {
      return;
    }

    _memories[index] = _memories[index].copyWith(content: normalized);
    AppLogger.info('workbench.memory.update', {'memoryId': memoryId});
    notifyListeners();
  }

  void deleteMemory(String memoryId) {
    final index = _memories.indexWhere((memory) => memory.id == memoryId);
    if (index < 0) {
      return;
    }
    _memories.removeAt(index);
    AppLogger.info('workbench.memory.delete', {'memoryId': memoryId});
    notifyListeners();
  }

  Future<Map<String, Object?>> callCapabilityFromWebApp({
    required AgentArtifact webApp,
    required String capabilityId,
    required Map<String, Object?> input,
  }) async {
    return _webAppBridge.callCapability(
      webApp: webApp,
      capabilityId: capabilityId,
      input: input,
      currentWorkspaceId: _workspaceId,
      memories: _memories,
      notes: _notes,
      artifacts: _artifacts,
      workspaces: _workspaces,
    );
  }

  Future<void> sendPrompt(String prompt) async {
    if (_isSending) {
      return;
    }

    final now = DateTime.now();
    final priorMessages = List<AgentMessage>.unmodifiable(_messages);
    AppLogger.info('workbench.prompt.send', {
      'workspaceId': _workspaceId,
      'length': prompt.length,
    });
    _messages.add(
      AgentMessage(
        id: 'msg-user-${now.microsecondsSinceEpoch}',
        role: MessageRole.user,
        createdAt: now,
        blocks: [MessageBlock.markdown(prompt)],
      ),
    );
    notifyListeners();

    final localResponse = _tryHandleLocalPrompt(prompt);
    if (localResponse != null) {
      _messages.add(localResponse);
      notifyListeners();
      return;
    }

    await _runConfiguredModel(prompt, priorMessages: priorMessages);
  }

  AgentMessage? _tryHandleLocalPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    if (prompt.contains('应用') ||
        normalized.contains('web app') ||
        normalized.contains('app')) {
      return _createWebAppArtifact(prompt);
    }
    return null;
  }

  Future<void> _runConfiguredModel(
    String prompt, {
    required List<AgentMessage> priorMessages,
  }) async {
    final provider = ModelProviders.aliyunBailianGlm5;
    final apiKey = await _apiKeyStore.readApiKey(provider.id);
    if (apiKey == null || apiKey.trim().isEmpty) {
      AppLogger.warning('workbench.model_api_key.missing', {
        'provider': provider.id,
      });
      _messages.add(_missingApiKeyResponse());
      notifyListeners();
      return;
    }

    _isSending = true;
    notifyListeners();

    try {
      await _agentLoop.run(
        provider: provider,
        apiKey: apiKey.trim(),
        prompt: prompt,
        workspace: currentWorkspace,
        workspaceId: _workspaceId,
        visibleMemories: visibleMemories,
        allMemories: _memories,
        allNotes: _notes,
        allArtifacts: _artifacts,
        allWorkspaces: _workspaces,
        noteStore: _noteStore,
        fileStore: _fileStore,
        priorMessages: priorMessages,
        addMessage: _messages.add,
        replaceMessage: _replaceMessage,
        notifyChange: notifyListeners,
        switchWorkspace: _switchWorkspaceFromAgent,
      );
    } on Object catch (error) {
      _messages.add(_modelErrorResponse(error.toString()));
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  AgentMessage _missingApiKeyResponse() {
    return AgentMessage(
      id: 'msg-missing-key-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.error(
          '缺少模型 API Key',
          '请先点击右上角“模型设置”，填写并保存阿里云百炼 API Key，然后再发送普通对话。',
        ),
      ],
    );
  }

  AgentMessage _modelErrorResponse(String detail) {
    return AgentMessage(
      id: 'msg-model-error-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.error('模型调用失败', detail)],
    );
  }

  void _replaceMessage(String messageId, AgentMessage message) {
    final index = _messages.indexWhere(
      (candidate) => candidate.id == messageId,
    );
    if (index < 0) {
      _messages.add(message);
      return;
    }
    _messages[index] = message;
  }

  void _switchWorkspaceFromAgent(String workspaceId) {
    final exists = _workspaces.any((workspace) => workspace.id == workspaceId);
    if (!exists || workspaceId == _workspaceId) {
      return;
    }
    _workspaceId = workspaceId;
    AppLogger.info('workbench.workspace.switch_by_agent', {
      'workspaceId': workspaceId,
    });
  }

  AgentMessage _createWebAppArtifact(String prompt) {
    final artifactId =
        'artifact-webapp-${DateTime.now().microsecondsSinceEpoch}';
    final artifact = AgentArtifact(
      id: artifactId,
      workspaceId: _workspaceId,
      type: ArtifactType.webApp,
      title: 'AI 生成的本地 Web 小应用',
      summary: '包含 manifest、独立沙箱、JSBridge 和 Capability 权限声明。',
      createdAt: DateTime.now(),
      metadata: {
        'entry': 'index.html',
        'permissions': WebAppRuntimeDefaults.permissions,
        'html': WebAppRuntimeDefaults.html,
        'databaseNamespace': WebAppDataNamespace.databaseForId(
          workspaceId: _workspaceId,
          webAppId: artifactId,
        ),
        'fileNamespace': WebAppDataNamespace.filesForId(
          workspaceId: _workspaceId,
          webAppId: artifactId,
        ),
      },
    );
    _artifacts.add(artifact);

    return AgentMessage(
      id: 'msg-webapp-${artifact.id}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.toolCall('artifact.create', {
          'type': 'web_app',
          'prompt': prompt,
        }),
        MessageBlock.toolResult('artifact.create', {
          'ok': true,
          'artifactId': artifact.id,
        }),
        MessageBlock.markdown(
          '已创建 Web App Artifact。后续实现会把 HTML/CSS/JS 写入本地应用库，'
          '并通过 `window.PhoneAgent.callCapability(id, input)` 调用手机能力。',
        ),
        MessageBlock.webAppCard(artifact.id, artifact.title),
      ],
    );
  }
}
