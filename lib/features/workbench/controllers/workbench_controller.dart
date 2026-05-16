import 'package:flutter/foundation.dart';

import '../../../data/seed/phone_agent_seed.dart';
import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/conversation/message_block.dart';
import '../../../domain/memory/memory.dart';
import '../../../domain/permissions/permission_policy.dart';
import '../../../domain/workspace/workspace.dart';

class WorkbenchController extends ChangeNotifier {
  WorkbenchController()
    : _workspaces = PhoneAgentSeed.workspaces(),
      _capabilities = PhoneAgentSeed.capabilities(),
      _messages = PhoneAgentSeed.messages(),
      _memories = PhoneAgentSeed.memories(),
      _artifacts = PhoneAgentSeed.artifacts();

  final List<AgentWorkspace> _workspaces;
  final List<CapabilityDefinition> _capabilities;
  final List<AgentMessage> _messages;
  final List<AgentMemory> _memories;
  final List<AgentArtifact> _artifacts;

  PermissionMode _permissionMode = PermissionMode.defaultMode;
  String _workspaceId = 'default';

  List<AgentWorkspace> get workspaces => List.unmodifiable(_workspaces);
  List<CapabilityDefinition> get capabilities =>
      List.unmodifiable(_capabilities);
  List<AgentMessage> get messages => List.unmodifiable(_messages);
  List<AgentMemory> get visibleMemories {
    return _memories
        .where(
          (memory) =>
              memory.scope == MemoryScope.global ||
              memory.workspaceId == _workspaceId,
        )
        .toList(growable: false);
  }

  List<AgentArtifact> get workspaceArtifacts {
    return _artifacts
        .where((artifact) => artifact.workspaceId == _workspaceId)
        .toList(growable: false);
  }

  List<PermissionMode> get permissionModes => PermissionMode.values;
  PermissionMode get permissionMode => _permissionMode;
  String get workspaceId => _workspaceId;

  AgentWorkspace get currentWorkspace {
    return _workspaces.firstWhere((workspace) => workspace.id == _workspaceId);
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
      description: '用于区分一组任务、文件、Artifact 和局部记忆。',
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

  void sendPrompt(String prompt) {
    final now = DateTime.now();
    _messages
      ..add(
        AgentMessage(
          id: 'msg-user-${now.microsecondsSinceEpoch}',
          role: MessageRole.user,
          createdAt: now,
          blocks: [MessageBlock.markdown(prompt)],
        ),
      )
      ..add(_simulateAgentResponse(prompt));
    notifyListeners();
  }

  AgentMessage _simulateAgentResponse(String prompt) {
    final normalized = prompt.toLowerCase();
    if (prompt.contains('记住') || normalized.contains('remember')) {
      return _remember(prompt);
    }
    if (prompt.contains('应用') ||
        normalized.contains('web app') ||
        normalized.contains('app')) {
      return _createWebAppArtifact(prompt);
    }
    if (prompt.contains('搜索') ||
        normalized.contains('search') ||
        prompt.contains('查')) {
      return _search(prompt);
    }
    return _defaultAssistantResponse(prompt);
  }

  AgentMessage _remember(String prompt) {
    final scope = prompt.contains('工作区')
        ? MemoryScope.workspace
        : MemoryScope.global;
    final memory = AgentMemory(
      id: 'memory-${DateTime.now().microsecondsSinceEpoch}',
      scope: scope,
      workspaceId: scope == MemoryScope.workspace ? _workspaceId : null,
      content: prompt.replaceFirst('记住', '').trim(),
      createdAt: DateTime.now(),
    );
    _memories.add(memory);

    return AgentMessage(
      id: 'msg-memory-${memory.id}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.toolCall('memory.create', {
          'scope': memory.scope.label,
          'workspaceId': memory.workspaceId,
          'content': memory.content,
        }),
        MessageBlock.toolResult('memory.create', {
          'ok': true,
          'memoryId': memory.id,
        }),
        MessageBlock.markdown('已写入 **${memory.scope.label}记忆**。'),
      ],
    );
  }

  AgentMessage _search(String prompt) {
    final artifact = AgentArtifact(
      id: 'artifact-search-${DateTime.now().microsecondsSinceEpoch}',
      workspaceId: _workspaceId,
      type: ArtifactType.report,
      title: '搜索摘要',
      summary: '围绕“$prompt”的搜索结果摘要 artifact。',
      createdAt: DateTime.now(),
    );
    _artifacts.add(artifact);

    return AgentMessage(
      id: 'msg-search-${artifact.id}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.toolCall('web.search', {'query': prompt}),
        MessageBlock.toolResult('web.search', {
          'ok': true,
          'results': [
            '搜索能力已进入 Capability Runtime',
            '真实 provider 后续替换当前 mock adapter',
          ],
        }),
        MessageBlock.markdown(
          '我会通过 `web.search` 做发现，再通过 `web.fetch` 读取指定网页。'
          '\n\n当前原型已经把搜索结果保存为 Artifact，便于后续引用。',
        ),
        MessageBlock.artifactCard(artifact.id, artifact.title),
      ],
    );
  }

  AgentMessage _createWebAppArtifact(String prompt) {
    final artifact = AgentArtifact(
      id: 'artifact-webapp-${DateTime.now().microsecondsSinceEpoch}',
      workspaceId: _workspaceId,
      type: ArtifactType.webApp,
      title: 'AI 生成的本地 Web 小应用',
      summary: '包含 manifest、独立沙箱、JSBridge 和 Capability 权限声明。',
      createdAt: DateTime.now(),
      metadata: const {
        'entry': 'index.html',
        'permissions': ['db.note.create', 'location.get_current', 'web.search'],
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

  AgentMessage _defaultAssistantResponse(String prompt) {
    return AgentMessage(
      id: 'msg-assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
      blocks: [
        MessageBlock.markdown(
          '我已经收到：$prompt\n\n'
          '当前第一版基座已经具备这些核心运行面：\n\n'
          '| 模块 | 状态 |\n'
          '| --- | --- |\n'
          '| Workspace | 默认与自定义入口 |\n'
          '| Memory | 全局和工作区记忆 |\n'
          '| Artifact | 报告、文件、Web App 等产物 |\n'
          '| Capability | 统一注册、权限和审计入口 |\n'
          '| Skill/MCP | 兼容层入口 |\n',
        ),
        MessageBlock.code(
          'js',
          'window.PhoneAgent.callCapability("web.search", { query: "mobile agent" });',
        ),
      ],
    );
  }
}
