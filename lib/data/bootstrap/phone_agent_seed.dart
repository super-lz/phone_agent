import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note.dart';
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
      content: '用户偏好中文回答，并倾向于第一性原理和可运行产物。',
      createdAt: now,
    ),
    AgentMemory(
      id: 'mem-global-2',
      content: 'Workspace 用于区分工作数据，不切分用户长期记忆。',
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

  static List<AgentNote> notes() => [
    AgentNote(
      id: 'note-default-1',
      workspaceId: 'default',
      title: 'Phone Agent 第一版目标',
      content: '把对话、工具调用、长期记忆、Workspace 数据和 Artifact 串成移动端闭环。',
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
      'project.create_web_app',
      CapabilityAdapter.file,
      CapabilityRisk.low,
    ),
    _capability(
      'file.apply_text_patch',
      CapabilityAdapter.file,
      CapabilityRisk.medium,
    ),
    _capability(
      'location.get_current',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
      requiredPermissions: const ['location'],
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
      requiredPermissions: const ['notifications'],
    ),
    _capability(
      'calendar.event.create',
      CapabilityAdapter.native,
      CapabilityRisk.medium,
    ),
    _capability(
      'time.get_current',
      CapabilityAdapter.native,
      CapabilityRisk.low,
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
    CapabilityRisk risk, {
    List<String> requiredPermissions = const [],
  }) {
    return CapabilityDefinition(
      id: id,
      description: 'Built-in capability: $id',
      inputSchema: const {'type': 'object'},
      outputSchema: const {'type': 'object'},
      risk: risk,
      requiredPermissions: requiredPermissions,
      adapter: adapter,
    );
  }
}
