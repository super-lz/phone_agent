import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/memory/memory.dart';
import '../../domain/workspace/workspace.dart';

class PhoneAgentSeed {
  static final now = DateTime.now();

  static List<AgentWorkspace> workspaces() => [
    AgentWorkspace(
      id: 'default',
      name: '默认',
      description: '跨学习、工作、生活都可使用的默认工作区。',
      createdAt: now,
    ),
    AgentWorkspace(
      id: 'study',
      name: '学习',
      description: '学习资料、课程计划、知识整理和练习任务。',
      createdAt: now,
    ),
    AgentWorkspace(
      id: 'work',
      name: '工作',
      description: '项目、会议、报告、代码和协作事项。',
      createdAt: now,
    ),
  ];

  static List<AgentMemory> memories() => [
    AgentMemory(
      id: 'mem-global-1',
      scope: MemoryScope.global,
      content: '用户偏好中文回答，并倾向于第一性原理和可运行产物。',
      createdAt: now,
    ),
    AgentMemory(
      id: 'mem-default-1',
      scope: MemoryScope.workspace,
      workspaceId: 'default',
      content: '默认工作区用于收纳跨场景任务和未分类产物。',
      createdAt: now,
    ),
  ];

  static List<AgentArtifact> artifacts() => [
    AgentArtifact(
      id: 'artifact-plan',
      workspaceId: 'default',
      type: ArtifactType.report,
      title: '第一版能力蓝图',
      summary: 'Conversation、Memory、Workspace、Artifact、Capability 的闭环说明。',
      createdAt: now,
    ),
  ];

  static List<CapabilityDefinition> capabilities() => [
    _capability('web.search', CapabilityAdapter.search, CapabilityRisk.low),
    _capability('web.fetch', CapabilityAdapter.search, CapabilityRisk.low),
    _capability(
      'file.read_app_file',
      CapabilityAdapter.file,
      CapabilityRisk.low,
    ),
    _capability(
      'file.write_app_file',
      CapabilityAdapter.file,
      CapabilityRisk.medium,
    ),
    _capability(
      'db.note.create',
      CapabilityAdapter.database,
      CapabilityRisk.low,
    ),
    _capability(
      'db.note.query',
      CapabilityAdapter.database,
      CapabilityRisk.low,
    ),
    _capability(
      'memory.create',
      CapabilityAdapter.memory,
      CapabilityRisk.medium,
    ),
    _capability('memory.query', CapabilityAdapter.memory, CapabilityRisk.low),
    _capability('memory.delete', CapabilityAdapter.memory, CapabilityRisk.high),
    _capability(
      'workspace.create',
      CapabilityAdapter.workspace,
      CapabilityRisk.low,
    ),
    _capability(
      'workspace.switch',
      CapabilityAdapter.workspace,
      CapabilityRisk.low,
    ),
    _capability(
      'artifact.create',
      CapabilityAdapter.artifact,
      CapabilityRisk.low,
    ),
    _capability(
      'artifact.query',
      CapabilityAdapter.artifact,
      CapabilityRisk.low,
    ),
    _capability(
      'location.get_current',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
    ),
    _capability(
      'clipboard.read',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
    ),
    _capability(
      'clipboard.write',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
    ),
    _capability(
      'notification.schedule',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
    ),
    _capability('device.info', CapabilityAdapter.native, CapabilityRisk.low),
    _capability(
      'webview.call_capability',
      CapabilityAdapter.webview,
      CapabilityRisk.medium,
    ),
    _capability(
      'skill.install',
      CapabilityAdapter.skill,
      CapabilityRisk.medium,
    ),
    _capability('skill.invoke', CapabilityAdapter.skill, CapabilityRisk.medium),
    _capability('mcp.connect', CapabilityAdapter.mcp, CapabilityRisk.high),
  ];

  static List<AgentMessage> messages() => [
    AgentMessage(
      id: 'msg-welcome',
      role: MessageRole.assistant,
      createdAt: now,
      blocks: [
        MessageBlock.markdown(
          '# Phone Agent\n'
          '这是第一版移动端 Agent 工作台基座。你可以让我搜索、记忆、创建 Artifact，'
          '也可以让我生成一个本地 Web 小应用。',
        ),
        MessageBlock.todoList([
          '对话工作台',
          'Workspace 与记忆',
          'Artifact 中心',
          'Capability Runtime',
          'WebView Bridge',
        ]),
      ],
    ),
  ];

  static CapabilityDefinition _capability(
    String id,
    CapabilityAdapter adapter,
    CapabilityRisk risk,
  ) {
    return CapabilityDefinition(
      id: id,
      description: 'Built-in capability: $id',
      inputSchema: const {'type': 'object'},
      outputSchema: const {'type': 'object'},
      risk: risk,
      requiredPermissions: const [],
      adapter: adapter,
    );
  }
}
