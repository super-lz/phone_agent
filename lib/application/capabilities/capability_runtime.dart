import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../data/capabilities/native_capability_adapter.dart';
import '../../data/capabilities/web_capability_adapter.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../../domain/workbench/workbench_store.dart';
import '../../domain/workspace/workspace.dart';
import 'artifact_capability_handler.dart';
import 'capability_execution_result.dart';
import 'capability_tool_definitions.dart';
import 'file_capability_handler.dart';
import 'memory_capability_handler.dart';
import 'native_capability_handler.dart';
import 'note_capability_handler.dart';
import 'project_capability_handler.dart';
import 'web_capability_handler.dart';
import 'workspace_capability_handler.dart';

class CapabilityRuntime {
  CapabilityRuntime({
    WebCapabilityAdapter? webAdapter,
    NativeCapabilityAdapter? nativeAdapter,
  }) : _webHandler = WebCapabilityHandler(webAdapter: webAdapter),
       _nativeHandler = NativeCapabilityHandler(
         adapter: nativeAdapter ?? NativeCapabilityAdapter(),
       );

  final MemoryCapabilityHandler _memoryHandler =
      const MemoryCapabilityHandler();
  final NoteCapabilityHandler _noteHandler = const NoteCapabilityHandler();
  final FileCapabilityHandler _fileHandler = const FileCapabilityHandler();
  final ArtifactCapabilityHandler _artifactHandler =
      const ArtifactCapabilityHandler();
  final ProjectCapabilityHandler _projectHandler =
      const ProjectCapabilityHandler();
  final WorkspaceCapabilityHandler _workspaceHandler =
      const WorkspaceCapabilityHandler();
  final WebCapabilityHandler _webHandler;
  final NativeCapabilityHandler _nativeHandler;
  final CapabilityToolDefinitions _toolDefinitions =
      const CapabilityToolDefinitions();

  Future<CapabilityExecutionResult> execute({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    List<AgentWorkspace>? workspaces,
    List<CapabilityDefinition>? capabilities,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    WorkbenchStore? workbenchStore,
    String? apiKey,
    PermissionMode permissionMode = PermissionMode.fullAccess,
    bool skipPermissionCheck = false,
  }) async {
    AppLogger.info('capability.execute.start', {
      'tool': toolCall.name,
      'workspaceId': workspaceId,
    });
    final permissionBlocked = skipPermissionCheck
        ? null
        : _permissionBlockedResult(
            toolCall: toolCall,
            capabilities: capabilities,
            permissionMode: permissionMode,
          );
    final result =
        permissionBlocked ??
        await _executeAllowed(
          toolCall: toolCall,
          workspaceId: workspaceId,
          memories: memories,
          notes: notes,
          artifacts: artifacts,
          workspaces: workspaces,
          noteStore: noteStore,
          fileStore: fileStore,
          apiKey: apiKey,
        );
    await _persistResultSideEffects(
      result: result,
      memories: memories,
      artifacts: artifacts,
      workspaces: workspaces,
      workbenchStore: workbenchStore,
    );
    await _recordInvocation(
      toolCall: toolCall,
      workspaceId: workspaceId,
      result: result,
      workbenchStore: workbenchStore,
      permissionMode: permissionMode,
      skippedPermissionCheck: skipPermissionCheck,
    );
    return result;
  }

  Future<CapabilityExecutionResult> _executeAllowed({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required List<AgentMemory> memories,
    required List<AgentNote> notes,
    required List<AgentArtifact> artifacts,
    List<AgentWorkspace>? workspaces,
    AgentNoteStore? noteStore,
    AppFileStore? fileStore,
    String? apiKey,
  }) async {
    switch (toolCall.name) {
      case 'memory_create':
        return _memoryHandler.create(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'memory_query':
        return _memoryHandler.query(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'memory_delete':
        return _memoryHandler.delete(
          arguments: toolCall.arguments,
          memories: memories,
        );
      case 'db_note_create':
        return await _noteHandler.create(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          notes: notes,
          noteStore: noteStore,
        );
      case 'db_note_query':
        return await _noteHandler.query(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          notes: notes,
          noteStore: noteStore,
        );
      case 'file_write_app_file':
        return await _fileHandler.write(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'file_read_app_file':
        return await _fileHandler.read(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'file_apply_text_patch':
        return await _fileHandler.applyTextPatch(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
        );
      case 'artifact_create':
        return _artifactHandler.create(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
        );
      case 'project_create_web_app':
        return await _projectHandler.createWebApp(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          fileStore: fileStore,
          artifacts: artifacts,
        );
      case 'artifact_query':
        return _artifactHandler.query(
          workspaceId: workspaceId,
          arguments: toolCall.arguments,
          artifacts: artifacts,
        );
      case 'workspace_create':
        return _workspaceHandler.create(
          arguments: toolCall.arguments,
          workspaces: workspaces,
        );
      case 'workspace_switch':
        return _workspaceHandler.switchWorkspace(
          arguments: toolCall.arguments,
          workspaces: workspaces,
        );
      case 'device_info':
        return await _nativeHandler.deviceInfo();
      case 'time_get_current':
        return await _nativeHandler.getCurrentTime();
      case 'clipboard_read':
        return await _nativeHandler.readClipboard();
      case 'clipboard_write':
        return await _nativeHandler.writeClipboard(
          arguments: toolCall.arguments,
        );
      case 'location_get_current':
        return await _nativeHandler.getCurrentLocation();
      case 'notification_schedule':
        return await _nativeHandler.scheduleNotification(
          arguments: toolCall.arguments,
        );
      case 'calendar_event_create':
        return await _nativeHandler.createCalendarEvent(
          arguments: toolCall.arguments,
        );
      case 'web_search':
        return await _webHandler.search(
          arguments: toolCall.arguments,
          apiKey: apiKey,
        );
      case 'web_fetch':
        return await _webHandler.fetch(
          arguments: toolCall.arguments,
          apiKey: apiKey,
        );
      case 'skill_install':
        return await _installSkill(toolCall.arguments);
      case 'skill_invoke':
        return _skillInvokeUnavailable(toolCall.arguments);
      case 'mcp_connect':
        return _connectMcp(toolCall.arguments);
      default:
        return CapabilityExecutionResult(
          capabilityId: toolCall.name,
          output: {'ok': false, 'error': 'Unsupported tool: ${toolCall.name}'},
        );
    }
  }

  Future<CapabilityExecutionResult> _installSkill(
    Map<String, Object?> arguments,
  ) async {
    final source = arguments['source'];
    if (source is! String || source.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {'ok': false, 'error': 'source is required'},
      );
    }
    final normalized = source.trim();
    if (normalized.endsWith('.zip') ||
        normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('git@')) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'skill_source_unavailable',
          'detail': '当前移动端安全执行后端尚未接入，暂不安装 zip 或 Git URL Skill。',
          'source': normalized,
        },
      );
    }
    final directory = Directory(normalized);
    if (!directory.existsSync()) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'not_found',
          'detail': 'Skill 目录不存在。',
          'source': normalized,
        },
      );
    }
    final manifest = File('${directory.path}/SKILL.md');
    if (!manifest.existsSync()) {
      return CapabilityExecutionResult(
        capabilityId: 'skill.install',
        output: {
          'ok': false,
          'error': 'invalid_skill',
          'detail': 'Skill 目录缺少 SKILL.md。',
          'source': normalized,
        },
      );
    }
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    return CapabilityExecutionResult(
      capabilityId: 'skill.install',
      output: {
        'ok': true,
        'skill': {
          'id': name,
          'source': normalized,
          'manifest': manifest.path,
          'status': 'indexed',
        },
      },
    );
  }

  CapabilityExecutionResult _skillInvokeUnavailable(
    Map<String, Object?> arguments,
  ) {
    final skillId = arguments['skill_id'] ?? arguments['skillId'];
    return CapabilityExecutionResult(
      capabilityId: 'skill.invoke',
      output: {
        'ok': false,
        'error': 'execution_backend_unavailable',
        'detail': '当前版本还没有安全脚本执行后端，不能直接执行 Skill 脚本。',
        if (skillId is String) 'skillId': skillId,
      },
    );
  }

  CapabilityExecutionResult _connectMcp(Map<String, Object?> arguments) {
    final rawUrl = arguments['url'];
    final rawTransport = arguments['transport'];
    final transport = rawTransport is String && rawTransport.trim().isNotEmpty
        ? rawTransport.trim().toLowerCase()
        : 'http';
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {'ok': false, 'error': 'url is required'},
      );
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': false,
          'error': 'invalid_url',
          'detail': '第一版 MCP 仅支持 HTTP/SSE URL。',
          'url': rawUrl.trim(),
        },
      );
    }
    if (transport != 'http' && transport != 'sse') {
      return CapabilityExecutionResult(
        capabilityId: 'mcp.connect',
        output: {
          'ok': false,
          'error': 'unsupported_transport',
          'detail': '第一版仅支持 http 或 sse；stdio 暂不执行本机进程。',
          'transport': transport,
        },
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'mcp.connect',
      output: {
        'ok': true,
        'connection': {
          'url': uri.toString(),
          'transport': transport,
          'status': 'configured',
        },
      },
    );
  }

  Future<void> _persistResultSideEffects({
    required CapabilityExecutionResult result,
    required List<AgentMemory> memories,
    required List<AgentArtifact> artifacts,
    required List<AgentWorkspace>? workspaces,
    required WorkbenchStore? workbenchStore,
  }) async {
    if (workbenchStore == null || result.output['ok'] != true) {
      return;
    }
    switch (result.capabilityId) {
      case 'memory.create':
        final memoryId = result.output['memoryId'];
        if (memoryId is String) {
          final index = memories.indexWhere((memory) => memory.id == memoryId);
          if (index >= 0) {
            await workbenchStore.upsertMemory(memories[index]);
          }
        }
        return;
      case 'memory.delete':
        final memoryId = result.output['memoryId'];
        if (memoryId is String) {
          await workbenchStore.deleteMemory(memoryId);
        }
        return;
      case 'artifact.create':
      case 'project.create_web_app':
        final artifactId = result.output['artifactId'];
        if (artifactId is String) {
          final index = artifacts.indexWhere(
            (artifact) => artifact.id == artifactId,
          );
          if (index >= 0) {
            await workbenchStore.upsertArtifact(artifacts[index]);
          }
        }
        return;
      case 'workspace.create':
        final workspaceId = result.output['activeWorkspaceId'];
        if (workspaceId is String && workspaces != null) {
          final index = workspaces.indexWhere(
            (workspace) => workspace.id == workspaceId,
          );
          if (index >= 0) {
            await workbenchStore.upsertWorkspace(workspaces[index]);
            await workbenchStore.saveCurrentWorkspaceId(workspaceId);
          }
        }
        return;
      case 'workspace.switch':
        final workspaceId = result.output['activeWorkspaceId'];
        if (workspaceId is String) {
          await workbenchStore.saveCurrentWorkspaceId(workspaceId);
        }
        return;
    }
  }

  Future<void> _recordInvocation({
    required ToolCallRequest toolCall,
    required String workspaceId,
    required CapabilityExecutionResult result,
    required WorkbenchStore? workbenchStore,
    required PermissionMode permissionMode,
    required bool skippedPermissionCheck,
  }) async {
    if (workbenchStore == null) {
      return;
    }
    final error = result.output['error'];
    final permissionDecision = result.output['permissionDecision'];
    final status = _statusForResult(result);
    await workbenchStore.recordInvocation(
      CapabilityInvocation(
        id: 'invocation-${DateTime.now().microsecondsSinceEpoch}',
        workspaceId: workspaceId,
        capabilityId: result.capabilityId,
        input: toolCall.arguments,
        status: status,
        permissionDecision: skippedPermissionCheck
            ? 'approved'
            : permissionDecision is String
            ? permissionDecision
            : permissionMode.name,
        output: result.output,
        error: error is String ? error : null,
        createdAt: DateTime.now(),
      ),
    );
  }

  CapabilityInvocationStatus _statusForResult(
    CapabilityExecutionResult result,
  ) {
    if (result.output['error'] == 'permission_confirmation_required') {
      return CapabilityInvocationStatus.pending;
    }
    if (result.output['error'] == 'permission_denied') {
      return CapabilityInvocationStatus.denied;
    }
    if (result.output['ok'] == true) {
      return CapabilityInvocationStatus.completed;
    }
    return CapabilityInvocationStatus.failed;
  }

  List<Map<String, Object?>> get toolDefinitions {
    return _toolDefinitions.all;
  }

  CapabilityExecutionResult? _permissionBlockedResult({
    required ToolCallRequest toolCall,
    required List<CapabilityDefinition>? capabilities,
    required PermissionMode permissionMode,
  }) {
    final definition = _definitionForToolName(toolCall.name, capabilities);
    if (definition == null) {
      return null;
    }
    final decision = PermissionPolicy(permissionMode).decide(definition);
    switch (decision) {
      case PermissionDecision.allow:
        return null;
      case PermissionDecision.ask:
        return CapabilityExecutionResult(
          capabilityId: definition.id,
          output: {
            'ok': false,
            'error': 'permission_confirmation_required',
            'detail': 'Capability ${definition.id} requires user confirmation.',
            'capabilityId': definition.id,
            'permissionDecision': decision.name,
            'permissionMode': permissionMode.name,
          },
        );
      case PermissionDecision.deny:
        return CapabilityExecutionResult(
          capabilityId: definition.id,
          output: {
            'ok': false,
            'error': 'permission_denied',
            'detail':
                'Capability ${definition.id} is denied by permission policy.',
            'capabilityId': definition.id,
            'permissionDecision': decision.name,
            'permissionMode': permissionMode.name,
          },
        );
    }
  }

  CapabilityDefinition? _definitionForToolName(
    String toolName,
    List<CapabilityDefinition>? capabilities,
  ) {
    if (capabilities == null || capabilities.isEmpty) {
      return null;
    }
    final capabilityId = _capabilityIdForToolName(toolName);
    for (final capability in capabilities) {
      if (capability.id == capabilityId) {
        return capability;
      }
    }
    return null;
  }

  String _capabilityIdForToolName(String toolName) {
    switch (toolName) {
      case 'memory_create':
        return 'memory.create';
      case 'memory_query':
        return 'memory.query';
      case 'memory_delete':
        return 'memory.delete';
      case 'db_note_create':
        return 'db.note.create';
      case 'db_note_query':
        return 'db.note.query';
      case 'file_write_app_file':
        return 'file.write_app_file';
      case 'file_read_app_file':
        return 'file.read_app_file';
      case 'file_apply_text_patch':
        return 'file.apply_text_patch';
      case 'artifact_create':
        return 'artifact.create';
      case 'project_create_web_app':
        return 'project.create_web_app';
      case 'artifact_query':
        return 'artifact.query';
      case 'workspace_create':
        return 'workspace.create';
      case 'workspace_switch':
        return 'workspace.switch';
      case 'device_info':
        return 'device.info';
      case 'time_get_current':
        return 'time.get_current';
      case 'clipboard_read':
        return 'clipboard.read';
      case 'clipboard_write':
        return 'clipboard.write';
      case 'location_get_current':
        return 'location.get_current';
      case 'notification_schedule':
        return 'notification.schedule';
      case 'calendar_event_create':
        return 'calendar.event.create';
      case 'web_search':
        return 'web.search';
      case 'web_fetch':
        return 'web.fetch';
      case 'skill_install':
        return 'skill.install';
      case 'skill_invoke':
        return 'skill.invoke';
      case 'mcp_connect':
        return 'mcp.connect';
      default:
        return toolName;
    }
  }
}
