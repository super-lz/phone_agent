import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../application/agent/agent_loop.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../application/capabilities/capability_execution_result.dart';
import '../../../application/capabilities/capability_result_presentation.dart';
import '../../../application/capabilities/capability_runtime.dart';
import '../../../application/capabilities/office_document_codec.dart';
import '../../../core/logging/app_logger.dart';
import '../../../data/bootstrap/phone_agent_seed.dart';
import '../../../data/models/model_api_key_store.dart';
import '../../../data/models/model_settings_store.dart';
import '../../../data/models/openai_compatible_chat_client.dart';
import '../../../domain/artifacts/artifact.dart';
import '../../../domain/artifacts/web_app_runtime_log.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/conversation/message_block.dart';
import '../../../domain/files/app_file_store.dart';
import '../../../domain/memory/memory.dart';
import '../../../domain/models/model_provider_config.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/notes/note_store.dart';
import '../../../domain/permissions/permission_policy.dart';
import '../../../domain/workbench/workbench_store.dart';
import '../../../domain/workspace/workspace.dart';
import '../../web_app_runtime/web_app_capability_bridge.dart';

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    ModelApiKeyStore? apiKeyStore,
    OpenAiCompatibleChatClient? chatClient,
    CapabilityRuntime? capabilityRuntime,
    ModelSettingsStore? modelSettingsStore,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    WorkbenchStore? workbenchStore,
  }) : this._(
         apiKeyStore: apiKeyStore ?? ModelApiKeyStore(),
         chatClient: chatClient ?? OpenAiCompatibleChatClient(),
         capabilityRuntime: capabilityRuntime ?? CapabilityRuntime(),
         modelSettingsStore: modelSettingsStore ?? InMemoryModelSettingsStore(),
         noteStore: noteStore ?? InMemoryAgentNoteStore(PhoneAgentSeed.notes()),
         fileStore: fileStore ?? InMemoryAppFileStore(),
         workbenchStore: workbenchStore ?? InMemoryWorkbenchStore(),
       );

  WorkbenchController._({
    required ModelApiKeyStore apiKeyStore,
    required OpenAiCompatibleChatClient chatClient,
    required CapabilityRuntime capabilityRuntime,
    required ModelSettingsStore modelSettingsStore,
    required AgentNoteStore noteStore,
    required AppFileStore fileStore,
    required WorkbenchStore workbenchStore,
  }) : _apiKeyStore = apiKeyStore,
       _modelSettingsStore = modelSettingsStore,
       _agentLoop = AgentLoop(
         chatClient: chatClient,
         capabilityRuntime: capabilityRuntime,
       ),
       _webAppBridge = WebAppCapabilityBridge(
         capabilityRuntime: capabilityRuntime,
         apiKeyStore: apiKeyStore,
         noteStore: noteStore,
         fileStore: fileStore,
         workbenchStore: workbenchStore,
       ),
       _noteStore = noteStore,
       _fileStore = fileStore,
       _workbenchStore = workbenchStore,
       _workspaces = PhoneAgentSeed.workspaces(),
       _capabilities = PhoneAgentSeed.capabilities(),
       _messages = PhoneAgentSeed.messages(),
       _memories = PhoneAgentSeed.memories(),
       _artifacts = PhoneAgentSeed.artifacts(),
       _notes = PhoneAgentSeed.notes() {
    unawaited(_loadNotes());
    _stateReady = _loadWorkbenchState();
    unawaited(_stateReady);
  }

  final ModelApiKeyStore _apiKeyStore;
  final ModelSettingsStore _modelSettingsStore;
  final AgentLoop _agentLoop;
  final WebAppCapabilityBridge _webAppBridge;
  final AgentNoteStore _noteStore;
  final AppFileStore _fileStore;
  final WorkbenchStore _workbenchStore;
  final List<AgentWorkspace> _workspaces;
  final List<CapabilityDefinition> _capabilities;
  final List<AgentMessage> _messages;
  final List<AgentMemory> _memories;
  final List<AgentArtifact> _artifacts;
  final List<AgentNote> _notes;
  final List<AppFileEntry> _workspaceFiles = [];
  final List<McpConnection> _mcpConnections = [];
  final List<AgentSkill> _skills = [];
  final List<Completer<void>> _foregroundWaiters = [];
  final OfficeDocumentCodec _officeCodec = const OfficeDocumentCodec();

  PermissionMode _permissionMode = PermissionMode.defaultMode;
  String _workspaceId = 'default';
  bool _isSending = false;
  bool _isAppInForeground = true;
  bool _isDisposed = false;
  AgentRunSnapshot? _currentRun;
  AgentRunControl? _currentRunControl;
  Future<void> _stateReady = Future<void>.value();

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

  List<AppFileEntry> get workspaceFiles => List.unmodifiable(_workspaceFiles);
  List<McpConnection> get mcpConnections => List.unmodifiable(_mcpConnections);
  List<AgentSkill> get skills => List.unmodifiable(_skills);

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
  bool get isAppInForeground => _isAppInForeground;
  AgentRunSnapshot? get currentRun => _currentRun;

  AgentWorkspace get currentWorkspace {
    return _workspaces.firstWhere((workspace) => workspace.id == _workspaceId);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _completeForegroundWaiters();
    unawaited(_noteStore.close());
    unawaited(_workbenchStore.close());
    super.dispose();
  }

  void setAppInForeground(bool isForeground) {
    if (_isAppInForeground == isForeground) {
      return;
    }
    _isAppInForeground = isForeground;
    AppLogger.info('workbench.lifecycle.changed', {
      'isForeground': isForeground,
      'isSending': _isSending,
    });
    if (isForeground) {
      _completeForegroundWaiters();
    }
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> _waitUntilForeground() {
    if (_isAppInForeground || _isDisposed) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _foregroundWaiters.add(completer);
    return completer.future;
  }

  void _completeForegroundWaiters() {
    final waiters = List<Completer<void>>.of(_foregroundWaiters);
    _foregroundWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  Future<void> _loadWorkbenchState() async {
    try {
      const defaultWorkspaceId = 'default';
      await _workbenchStore.initialize(
        seedWorkspaces: PhoneAgentSeed.workspaces(),
        seedMemories: PhoneAgentSeed.memories(),
        seedArtifacts: PhoneAgentSeed.artifacts(),
        seedMessages: PhoneAgentSeed.messages(),
        defaultWorkspaceId: defaultWorkspaceId,
      );
      final loadedWorkspaces = await _workbenchStore.loadWorkspaces();
      final loadedMemories = await _workbenchStore.loadMemories();
      final loadedArtifacts = await _workbenchStore.loadArtifacts();
      final loadedMcpConnections = await _workbenchStore.loadMcpConnections();
      final loadedSkills = await _workbenchStore.loadSkills();
      final storedWorkspaceId = await _workbenchStore.loadCurrentWorkspaceId();
      final nextWorkspaceId =
          loadedWorkspaces.any((workspace) => workspace.id == storedWorkspaceId)
          ? storedWorkspaceId!
          : defaultWorkspaceId;
      final loadedMessages = await _workbenchStore.loadMessages(
        nextWorkspaceId,
      );

      _workspaces
        ..clear()
        ..addAll(loadedWorkspaces);
      _memories
        ..clear()
        ..addAll(loadedMemories);
      _artifacts
        ..clear()
        ..addAll(loadedArtifacts);
      _mcpConnections
        ..clear()
        ..addAll(loadedMcpConnections);
      _skills
        ..clear()
        ..addAll(loadedSkills);
      _workspaceId = nextWorkspaceId;
      _messages
        ..clear()
        ..addAll(loadedMessages);
      if (_messages.isEmpty && _workspaceId == defaultWorkspaceId) {
        _messages.addAll(PhoneAgentSeed.messages());
        await _persistCurrentMessages();
      }
      await _workbenchStore.saveCurrentWorkspaceId(_workspaceId);
      await _initializeMcpConnections();
      await _refreshWorkspaceFiles(notify: false);
      AppLogger.info('workbench.state.loaded', {
        'workspaceCount': _workspaces.length,
        'memoryCount': _memories.length,
        'artifactCount': _artifacts.length,
        'messageCount': _messages.length,
        'workspaceId': _workspaceId,
      });
      if (!_isDisposed) {
        notifyListeners();
      }
    } on Object catch (error) {
      AppLogger.warning('workbench.state.load_failed', {
        'error': error.toString(),
      });
    }
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

  Future<void> _persistCurrentMessages() async {
    for (final message in _messages) {
      await _workbenchStore.upsertMessage(
        workspaceId: _workspaceId,
        message: message,
      );
    }
  }

  void _persistMessage(AgentMessage message, {String? workspaceId}) {
    unawaited(
      _workbenchStore.upsertMessage(
        workspaceId: workspaceId ?? _workspaceId,
        message: message,
      ),
    );
  }

  void _persistCollections() {
    for (final workspace in _workspaces) {
      unawaited(_workbenchStore.upsertWorkspace(workspace));
    }
    for (final memory in _memories) {
      unawaited(_workbenchStore.upsertMemory(memory));
    }
    for (final artifact in _artifacts) {
      unawaited(_workbenchStore.upsertArtifact(artifact));
    }
    for (final connection in _mcpConnections) {
      unawaited(_workbenchStore.upsertMcpConnection(connection));
    }
    for (final skill in _skills) {
      unawaited(_workbenchStore.upsertSkill(skill));
    }
    unawaited(_workbenchStore.saveCurrentWorkspaceId(_workspaceId));
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
    final exists = _workspaces.any((workspace) => workspace.id == workspaceId);
    if (!exists) {
      return;
    }
    _workspaceId = workspaceId;
    _messages.clear();
    _workspaceFiles.clear();
    unawaited(_workbenchStore.saveCurrentWorkspaceId(workspaceId));
    unawaited(_loadMessagesForWorkspace(workspaceId));
    unawaited(_refreshWorkspaceFiles());
    notifyListeners();
  }

  Future<void> _loadMessagesForWorkspace(String workspaceId) async {
    try {
      final loadedMessages = await _workbenchStore.loadMessages(workspaceId);
      if (_isDisposed || workspaceId != _workspaceId) {
        return;
      }
      _messages
        ..clear()
        ..addAll(loadedMessages);
      notifyListeners();
    } on Object catch (error) {
      AppLogger.warning('workbench.messages.load_failed', {
        'workspaceId': workspaceId,
        'error': error.toString(),
      });
    }
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
    _messages.clear();
    _workspaceFiles.clear();
    final message = AgentMessage(
      id: 'msg-workspace-$next',
      role: MessageRole.system,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.markdown('已创建并切换到 **${workspace.name}**。')],
    );
    _messages.add(message);
    unawaited(_workbenchStore.upsertWorkspace(workspace));
    unawaited(_workbenchStore.saveCurrentWorkspaceId(workspace.id));
    _persistMessage(message, workspaceId: workspace.id);
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
    unawaited(_workbenchStore.upsertMemory(memory));
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
    unawaited(_workbenchStore.upsertMemory(_memories[index]));
    AppLogger.info('workbench.memory.update', {'memoryId': memoryId});
    notifyListeners();
  }

  void deleteMemory(String memoryId) {
    final index = _memories.indexWhere((memory) => memory.id == memoryId);
    if (index < 0) {
      return;
    }
    _memories.removeAt(index);
    unawaited(_workbenchStore.deleteMemory(memoryId));
    AppLogger.info('workbench.memory.delete', {'memoryId': memoryId});
    notifyListeners();
  }

  Future<void> approveCapabilityRequest(Map<String, Object?> data) async {
    final requestId = data['requestId'];
    final toolName = data['toolName'];
    final workspaceId = data['workspaceId'];
    final rawInput = data['input'];
    if (requestId is! String ||
        toolName is! String ||
        workspaceId is! String ||
        rawInput is! Map<Object?, Object?>) {
      return;
    }
    _setApprovalStatus(requestId, 'approved');
    final input = rawInput.map((key, value) => MapEntry(key.toString(), value));
    final apiKey = await _apiKeyStore.readApiKey(
      ModelProviders.aliyunBailianQwenFlash.id,
    );
    final result = await _agentLoop.executeApprovedTool(
      toolCall: ToolCallRequest(
        id: requestId,
        name: toolName,
        arguments: input,
      ),
      workspaceId: workspaceId,
      allMemories: _memories,
      allNotes: _notes,
      allArtifacts: _artifacts,
      allWorkspaces: _workspaces,
      allSkills: _skills,
      allCapabilities: _capabilities,
      noteStore: _noteStore,
      fileStore: _fileStore,
      workbenchStore: _workbenchStore,
      apiKey: apiKey,
      permissionMode: _permissionMode,
      switchWorkspace: _switchWorkspaceFromAgent,
    );

    if (result.capabilityId == 'mcp.connect' && result.output['ok'] == true) {
      final connData = result.output['connection'] as Map<String, Object?>;
      final url = connData['url'] as String;
      final transport = connData['transport'] as String;
      if (!_mcpConnections.any((c) => c.url == url)) {
        final conn = McpConnection(
          url: url,
          transport: transport,
          createdAt: DateTime.now(),
        );
        _mcpConnections.add(conn);
        unawaited(_workbenchStore.upsertMcpConnection(conn));
      }
    }

    if (result.capabilityId == 'skill.install' && result.output['ok'] == true) {
      final skillData = result.output['skill'] as Map<String, Object?>;
      final skillId = skillData['id'] as String;
      if (!_skills.any((s) => s.id == skillId)) {
        final skill = AgentSkill(
          id: skillId,
          name: skillData['name'] as String? ?? skillId,
          description: skillData['description'] as String? ?? '',
          script: skillData['script'] as String? ?? '',
          manifestPath: skillData['manifest'] as String?,
          createdAt: DateTime.now(),
        );
        _skills.add(skill);
        unawaited(_workbenchStore.upsertSkill(skill));
      }
    }

    final presentation = presentCapabilityResult(
      capabilityId: result.capabilityId,
      output: result.output,
    );
    _addMessage(
      AgentMessage(
        id: 'msg-approved-${DateTime.now().microsecondsSinceEpoch}',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        blocks: [
          MessageBlock.toolCall(toolName, input),
          MessageBlock.toolResult(result.capabilityId, result.output),
          ..._artifactBlocksFor(result),
          MessageBlock.markdown(presentation.summary),
        ],
      ),
    );
    _persistCollections();
    await _refreshWorkspaceFiles(notify: false);
    notifyListeners();
  }

  void denyCapabilityRequest(Map<String, Object?> data) {
    final requestId = data['requestId'];
    final toolName = data['toolName'];
    final capabilityId = data['capabilityId'];
    final rawInput = data['input'];
    if (requestId is! String ||
        toolName is! String ||
        capabilityId is! String ||
        rawInput is! Map<Object?, Object?>) {
      return;
    }
    _setApprovalStatus(requestId, 'denied');
    final input = rawInput.map((key, value) => MapEntry(key.toString(), value));
    unawaited(
      _workbenchStore.recordInvocation(
        CapabilityInvocation(
          id: 'invocation-${DateTime.now().microsecondsSinceEpoch}',
          workspaceId: _workspaceId,
          capabilityId: capabilityId,
          input: input,
          status: CapabilityInvocationStatus.denied,
          permissionDecision: 'denied_by_user',
          output: const {'ok': false, 'error': 'permission_denied'},
          error: 'permission_denied',
          createdAt: DateTime.now(),
        ),
      ),
    );
    _addMessage(
      AgentMessage(
        id: 'msg-denied-${DateTime.now().microsecondsSinceEpoch}',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
        blocks: [
          MessageBlock.toolResult(capabilityId, const {
            'ok': false,
            'error': 'permission_denied',
            'detail': '用户已拒绝执行该能力。',
          }),
        ],
      ),
    );
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
      capabilities: _capabilities,
    );
  }

  Future<void> sendPrompt(
    String prompt, {
    List<MessageBlock> attachments = const [],
  }) async {
    await _stateReady;
    if (_isSending) {
      return;
    }

    final now = DateTime.now();
    final priorMessages = List<AgentMessage>.unmodifiable(_messages);
    final modelPrompt = await _promptWithAttachmentContext(prompt, attachments);
    AppLogger.info('workbench.prompt.send', {
      'workspaceId': _workspaceId,
      'length': prompt.length,
      'attachmentCount': attachments.length,
      'prompt': prompt,
      'modelPrompt': jsonEncode(
        OpenAiCompatibleChatClient.diagnosticPayloadForLog(modelPrompt),
      ),
    });
    _addMessage(
      AgentMessage(
        id: 'msg-user-${now.microsecondsSinceEpoch}',
        role: MessageRole.user,
        createdAt: now,
        blocks: [MessageBlock.markdown(prompt), ...attachments],
      ),
    );
    notifyListeners();

    await _runConfiguredModel(modelPrompt, priorMessages: priorMessages);
  }

  void cancelCurrentRun() {
    final control = _currentRunControl;
    if (!_isSending || control == null || control.isCancelled) {
      return;
    }
    control.cancel();
    _currentRun = AgentRunSnapshot(
      phase: AgentRunPhase.cancelled,
      detail: control.reason,
      toolCallsUsed: _currentRun?.toolCallsUsed ?? 0,
      maxToolCalls: _currentRun?.maxToolCalls ?? 0,
      startedAt: _currentRun?.startedAt ?? DateTime.now(),
    );
    AppLogger.warning('workbench.agent_run.cancel_requested', {
      'workspaceId': _workspaceId,
      'reason': control.reason,
    });
    notifyListeners();
  }

  Future<void> refreshWorkspaceFiles() async {
    await _refreshWorkspaceFiles();
  }

  Future<void> _initializeMcpConnections() async {
    for (final conn in _mcpConnections) {
      try {
        await _agentLoop.capabilityRuntime.mcpManager.connect(
          conn.url,
          conn.transport,
        );
      } catch (e) {
        AppLogger.warning('workbench.mcp.auto_connect_failed', {
          'url': conn.url,
          'error': e.toString(),
        });
      }
    }
  }

  Future<void> clearLocalWorkspaceData() async {
    await _stateReady;
    if (_isSending) {
      throw StateError('正在生成回复，暂时不能清理本地数据。');
    }

    final defaultWorkspace = PhoneAgentSeed.workspaces().firstWhere(
      (workspace) => workspace.id == 'default',
    );
    final clearedMessage = AgentMessage(
      id: 'msg-local-clear-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.system,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.markdown('本地工作区内容已清理。模型设置和 API Key 已保留。')],
    );

    await _fileStore.clearAll();
    await _noteStore.resetLocalData();
    await _workbenchStore.resetLocalData(
      defaultWorkspace: defaultWorkspace,
      defaultMessages: [clearedMessage],
    );

    _workspaceId = defaultWorkspace.id;
    _workspaces
      ..clear()
      ..add(defaultWorkspace);
    _messages
      ..clear()
      ..add(clearedMessage);
    _memories.clear();
    _artifacts.clear();
    _notes.clear();
    _workspaceFiles.clear();
    AppLogger.info('workbench.local_data.cleared', {
      'workspaceId': _workspaceId,
    });
    notifyListeners();
  }

  Future<AppFileReadResult> readWorkspaceFile(AppFileEntry entry) {
    return _fileStore.readText(
      workspaceId: _workspaceId,
      path: entry.path,
      maxChars: 5 * 1024 * 1024,
    );
  }

  Future<AppFileReadResult> readWebAppResource({
    required AgentArtifact webApp,
    required String path,
    required int maxChars,
  }) {
    return _fileStore.readText(
      workspaceId: webApp.workspaceId,
      path: path,
      maxChars: maxChars,
    );
  }

  Future<void> recordWebAppRuntimeLog({
    required AgentArtifact webApp,
    required WebAppRuntimeLogEntry entry,
  }) async {
    final logPath = WebAppRuntimeLogPaths.forArtifact(webApp);
    try {
      final existing = await _readExistingRuntimeLog(
        workspaceId: webApp.workspaceId,
        path: logPath,
      );
      await _fileStore.writeText(
        workspaceId: webApp.workspaceId,
        path: logPath,
        content: _runtimeLogContent(existing, entry.toJsonLine()),
        overwrite: true,
      );
      if (webApp.workspaceId == _workspaceId &&
          !_workspaceFiles.any((file) => file.path == logPath)) {
        await _refreshWorkspaceFiles(notify: false);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning('webapp.runtime_log.write_failed', {
        'workspaceId': webApp.workspaceId,
        'artifactId': webApp.id,
        'path': logPath,
        'error': error.toString(),
      });
      AppLogger.error(
        'webapp.runtime_log.write_failed.stack',
        error,
        stackTrace,
      );
    }
  }

  Future<String> _readExistingRuntimeLog({
    required String workspaceId,
    required String path,
  }) async {
    try {
      final result = await _fileStore.readText(
        workspaceId: workspaceId,
        path: path,
        maxChars: 96 * 1024,
      );
      return result.content;
    } on AppFileStoreException catch (error) {
      if (error.code == 'not_found') {
        return '';
      }
      rethrow;
    }
  }

  String _runtimeLogContent(String existing, String nextLine) {
    const maxChars = 96 * 1024;
    final combined = '$existing$nextLine';
    if (combined.length <= maxChars) {
      return combined;
    }
    return combined.substring(combined.length - maxChars);
  }

  Future<Object> _promptWithAttachmentContext(
    String prompt,
    List<MessageBlock> attachments,
  ) async {
    if (attachments.isEmpty) {
      return prompt;
    }
    final lines = <String>[];
    final imageParts = <Map<String, Object?>>[];
    for (final attachment in attachments) {
      final imagePart = await _imagePromptPart(attachment);
      if (imagePart.contentPart != null) {
        imageParts.add(imagePart.contentPart!);
      }
      lines.add(
        await _attachmentContextLine(attachment, imageDetail: imagePart.detail),
      );
    }
    final textPrompt =
        '$prompt\n\n用户随消息附加了以下本地附件摘要；文本类文件已尽量读取正文摘录；'
        '图片类附件会尽量作为多模态 image_url 输入提供给模型，失败时会明确写明原因：\n'
        '${lines.join('\n')}';
    if (imageParts.isEmpty) {
      return textPrompt;
    }
    return <Map<String, Object?>>[
      {'type': 'text', 'text': textPrompt},
      ...imageParts,
    ];
  }

  Future<String> _attachmentContextLine(
    MessageBlock block, {
    String? imageDetail,
  }) async {
    final type = block.type == MessageBlockType.image ? '图片' : '文件';
    final name = block.data['name'] as String? ?? '未命名附件';
    final uri = block.data['uri'] as String? ?? '';
    final bytes = block.data['bytes'];
    final mimeType = block.data['mimeType'];
    final extension = block.data['extension'];
    final parts = <String>['- $type: $name'];
    if (bytes is int) {
      parts.add('$bytes bytes');
    }
    if (mimeType is String && mimeType.isNotEmpty) {
      parts.add(mimeType);
    }
    if (extension is String && extension.isNotEmpty) {
      parts.add('扩展名 .$extension');
    }
    if (uri.isNotEmpty) {
      parts.add(uri);
    }
    final textPreview = await _textPreviewForAttachment(block);
    if (textPreview != null && textPreview.isNotEmpty) {
      parts.add('正文摘录：$textPreview');
    } else if (block.type == MessageBlockType.image) {
      parts.add(imageDetail ?? '图片内容：unavailable');
    }
    return parts.join(' · ');
  }

  Future<_ImagePromptPart> _imagePromptPart(MessageBlock block) async {
    if (block.type != MessageBlockType.image) {
      return const _ImagePromptPart();
    }
    final uri = block.data['uri'];
    if (uri is! String || uri.isEmpty) {
      return const _ImagePromptPart(detail: '图片内容：缺少本地 URI，无法发送给模型。');
    }
    try {
      final fileUri = Uri.parse(uri);
      if (!fileUri.isScheme('file')) {
        return _ImagePromptPart(detail: '图片内容：非本地 file URI，无法发送给模型：$uri');
      }
      final file = File(fileUri.toFilePath());
      if (!await file.exists()) {
        return _ImagePromptPart(detail: '图片内容：本地文件不存在，无法发送给模型：$uri');
      }
      final length = await file.length();
      const maxImageBytes = 8 * 1024 * 1024;
      if (length > maxImageBytes) {
        return _ImagePromptPart(detail: '图片内容：文件超过 8 MB，未发送给模型；请压缩后重试。');
      }
      final bytes = await file.readAsBytes();
      final mimeType = _imageMimeTypeForModel(block, fileUri);
      return _ImagePromptPart(
        detail: '图片内容：已作为多模态 image_url 输入发送给模型。',
        contentPart: {
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
        },
      );
    } on Object catch (error) {
      return _ImagePromptPart(detail: '图片内容：读取失败：$error');
    }
  }

  String _imageMimeTypeForModel(MessageBlock block, Uri fileUri) {
    final explicitMimeType = block.data['mimeType'];
    if (explicitMimeType is String && explicitMimeType.isNotEmpty) {
      return explicitMimeType;
    }
    final path = fileUri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (path.endsWith('.gif')) {
      return 'image/gif';
    }
    if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/png';
  }

  Future<String?> _textPreviewForAttachment(MessageBlock block) async {
    if (block.type != MessageBlockType.fileAttachment) {
      return null;
    }
    final uri = block.data['uri'];
    if (uri is! String || uri.isEmpty) {
      return null;
    }
    final extension = (block.data['extension'] as String? ?? '').toLowerCase();

    // Support Office and PDF extraction
    final isOfficeOrPdf = const {
      'pdf',
      'docx',
      'xlsx',
      'pptx',
    }.contains(extension);

    const textExtensions = {
      'txt',
      'md',
      'json',
      'csv',
      'log',
      'yaml',
      'yml',
      'xml',
      'html',
      'css',
      'js',
      'ts',
      'dart',
    };

    if (!textExtensions.contains(extension) && !isOfficeOrPdf) {
      return null;
    }

    try {
      final fileUri = Uri.parse(uri);
      if (!fileUri.isScheme('file')) {
        return null;
      }
      final file = File(fileUri.toFilePath());
      if (!await file.exists()) {
        return null;
      }

      if (isOfficeOrPdf) {
        final bytes = await file.readAsBytes();
        final content = _officeCodec.extractText(file.path, bytes);
        final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (normalized.length <= 6000) {
          return normalized;
        }
        return '${normalized.substring(0, 6000)}...';
      }

      final content = await file.readAsString();
      final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= 4000) {
        return normalized;
      }
      return '${normalized.substring(0, 4000)}...';
    } on Object catch (error) {
      return '读取失败：$error';
    }
  }

  Future<void> _runConfiguredModel(
    Object prompt, {
    required List<AgentMessage> priorMessages,
  }) async {
    final provider = await _configuredProvider();
    if (!provider.canRunConnectionTest) {
      _addMessage(_unsupportedProviderResponse(provider));
      notifyListeners();
      return;
    }
    final storedApiKey = provider.requiresApiKey
        ? await _apiKeyStore.readApiKey(provider.id)
        : '';
    final apiKey = storedApiKey?.trim() ?? '';
    if (provider.requiresApiKey && apiKey.isEmpty) {
      AppLogger.warning('workbench.model_api_key.missing', {
        'provider': provider.id,
      });
      _addMessage(_missingApiKeyResponse(provider));
      notifyListeners();
      return;
    }

    _isSending = true;
    final runControl = AgentRunControl();
    _currentRunControl = runControl;
    _currentRun = AgentRunSnapshot(
      phase: AgentRunPhase.routing,
      detail: '正在启动本轮 Agent 任务。',
      toolCallsUsed: 0,
      maxToolCalls: _agentLoop.budget.maxToolCalls,
      startedAt: DateTime.now(),
    );
    notifyListeners();

    try {
      await _agentLoop.run(
        provider: provider,
        apiKey: apiKey,
        prompt: prompt,
        workspace: currentWorkspace,
        workspaceId: _workspaceId,
        visibleMemories: visibleMemories,
        allMemories: _memories,
        allNotes: _notes,
        allArtifacts: _artifacts,
        allWorkspaces: _workspaces,
        allSkills: _skills,
        allCapabilities: _capabilities,
        noteStore: _noteStore,
        fileStore: _fileStore,
        workbenchStore: _workbenchStore,
        permissionMode: _permissionMode,
        priorMessages: priorMessages,
        addMessage: _addMessage,
        replaceMessage: _replaceMessage,
        notifyChange: notifyListeners,
        switchWorkspace: _switchWorkspaceFromAgent,
        isForeground: () => _isAppInForeground,
        waitUntilForeground: _waitUntilForeground,
        runControl: runControl,
        reportRunSnapshot: _setCurrentRun,
      );
    } on AgentRunCancelledException catch (error) {
      AppLogger.warning('workbench.agent_run.cancelled', {
        'workspaceId': _workspaceId,
        'reason': error.message,
      });
      _addMessage(_agentRunCancelledResponse(error.message));
    } on Object catch (error) {
      _addMessage(_modelErrorResponse(error.toString()));
    } finally {
      _persistCollections();
      await _refreshWorkspaceFiles(notify: false);
      _isSending = false;
      _currentRunControl = null;
      _currentRun = null;
      notifyListeners();
    }
  }

  void _setCurrentRun(AgentRunSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }
    final previous = _currentRun;
    final isDuplicate =
        previous?.phase == snapshot.phase &&
        previous?.detail == snapshot.detail &&
        previous?.toolCallsUsed == snapshot.toolCallsUsed &&
        previous?.maxToolCalls == snapshot.maxToolCalls &&
        previous?.currentToolName == snapshot.currentToolName;
    if (isDuplicate) {
      return;
    }
    _currentRun = snapshot;
    AppLogger.info('workbench.agent_run.status', {
      'phase': snapshot.phase.name,
      'detail': snapshot.detail,
      'toolCallsUsed': snapshot.toolCallsUsed,
      'maxToolCalls': snapshot.maxToolCalls,
      if (snapshot.currentToolName != null)
        'currentToolName': snapshot.currentToolName,
    });
    notifyListeners();
  }

  Future<void> _refreshWorkspaceFiles({bool notify = true}) async {
    try {
      final files = await _fileStore.listFiles(workspaceId: _workspaceId);
      if (_isDisposed) {
        return;
      }
      _workspaceFiles
        ..clear()
        ..addAll(files);
      if (notify) {
        notifyListeners();
      }
    } on Object catch (error) {
      AppLogger.warning('workbench.files.load_failed', {
        'workspaceId': _workspaceId,
        'error': error.toString(),
      });
    }
  }

  Future<ModelProviderConfig> _configuredProvider() async {
    final provider = ModelProviders.byIdOrDefault(
      await _modelSettingsStore.readSelectedProviderId(),
    );
    final modelName = await _modelSettingsStore.readModelName(provider.id);
    final normalized = modelName?.trim();
    if (normalized == null || normalized.isEmpty) {
      return provider;
    }
    return provider.copyWith(model: normalized);
  }

  AgentMessage _missingApiKeyResponse(ModelProviderConfig provider) {
    return AgentMessage(
      id: 'msg-missing-key-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.error(
          '缺少模型 API Key',
          '当前选择的是${provider.vendorName}，普通对话需要 API Key。'
              '请进入“模型设置”填写并保存对应接入方的 API Key。',
        ),
      ],
    );
  }

  AgentMessage _unsupportedProviderResponse(ModelProviderConfig provider) {
    return AgentMessage(
      id: 'msg-unsupported-provider-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.error(
          '模型接入暂不可用',
          '${provider.vendorName} 已加入模型配置列表，但官方 API endpoint 尚未确认。'
              '当前版本可以保存它的 Key 和模型选择，普通对话请先切换到已启用的接入方。',
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

  AgentMessage _agentRunCancelledResponse(String detail) {
    return AgentMessage(
      id: 'msg-agent-cancelled-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [MessageBlock.error('本轮任务已停止', detail)],
    );
  }

  void _addMessage(AgentMessage message) {
    _messages.add(message);
    _persistMessage(message);
  }

  void _setApprovalStatus(String requestId, String status) {
    for (
      var messageIndex = 0;
      messageIndex < _messages.length;
      messageIndex++
    ) {
      final message = _messages[messageIndex];
      var changed = false;
      final blocks = message.blocks
          .map((block) {
            if (block.type != MessageBlockType.approvalRequest ||
                block.data['requestId'] != requestId) {
              return block;
            }
            changed = true;
            return MessageBlock(
              type: MessageBlockType.approvalRequest,
              data: {...block.data, 'status': status},
            );
          })
          .toList(growable: false);
      if (!changed) {
        continue;
      }
      final updated = AgentMessage(
        id: message.id,
        role: message.role,
        createdAt: message.createdAt,
        blocks: blocks,
      );
      _messages[messageIndex] = updated;
      _persistMessage(updated);
      return;
    }
  }

  List<MessageBlock> _artifactBlocksFor(CapabilityExecutionResult result) {
    if (result.output['ok'] != true ||
        result.capabilityId != 'artifact.create' &&
            result.capabilityId != 'project.create_web_app' &&
            result.capabilityId != 'project.update_web_app' &&
            result.capabilityId != 'project.revert_web_app') {
      return const [];
    }
    final artifactId = result.output['artifactId'];
    final title = result.output['title'];
    final type = result.output['type'];
    if (artifactId is! String || title is! String) {
      return const [];
    }
    if (_isWebAppArtifactType(type)) {
      return [MessageBlock.webAppCard(artifactId, title)];
    }
    return [MessageBlock.artifactCard(artifactId, title)];
  }

  bool _isWebAppArtifactType(Object? type) {
    return type is String &&
        type.trim().replaceAll('_', '').replaceAll('-', '').toLowerCase() ==
            'webapp';
  }

  void _replaceMessage(String messageId, AgentMessage message) {
    final index = _messages.indexWhere(
      (candidate) => candidate.id == messageId,
    );
    if (index < 0) {
      _messages.add(message);
      _persistMessage(message);
      return;
    }
    _messages[index] = message;
    _persistMessage(message);
  }

  void _switchWorkspaceFromAgent(String workspaceId) {
    final exists = _workspaces.any((workspace) => workspace.id == workspaceId);
    if (!exists || workspaceId == _workspaceId) {
      return;
    }
    _workspaceId = workspaceId;
    unawaited(_workbenchStore.saveCurrentWorkspaceId(workspaceId));
    AppLogger.info('workbench.workspace.switch_by_agent', {
      'workspaceId': workspaceId,
    });
  }
}

class _ImagePromptPart {
  const _ImagePromptPart({this.detail, this.contentPart});

  final String? detail;
  final Map<String, Object?>? contentPart;
}
