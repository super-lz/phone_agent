import '../../domain/workspace/workspace.dart';
import 'capability_execution_result.dart';

class WorkspaceCapabilityHandler {
  const WorkspaceCapabilityHandler();

  CapabilityExecutionResult create({
    required Map<String, Object?> arguments,
    required List<AgentWorkspace>? workspaces,
  }) {
    final workspaceList = workspaces;
    if (workspaceList == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'workspace.create',
        output: {'ok': false, 'error': 'workspace store unavailable'},
      );
    }

    final rawName = arguments['name'];
    if (rawName is! String || rawName.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'workspace.create',
        output: {'ok': false, 'error': 'name is required'},
      );
    }
    final rawDescription = arguments['description'];
    final description =
        rawDescription is String && rawDescription.trim().isNotEmpty
        ? rawDescription.trim()
        : '由 Agent 创建的工作区。';

    final workspace = AgentWorkspace(
      id: 'workspace-${DateTime.now().microsecondsSinceEpoch}',
      name: rawName.trim(),
      description: description,
      createdAt: DateTime.now(),
    );
    workspaceList.add(workspace);
    return CapabilityExecutionResult(
      capabilityId: 'workspace.create',
      output: {
        'ok': true,
        'workspaceId': workspace.id,
        'activeWorkspaceId': workspace.id,
        'name': workspace.name,
        'description': workspace.description,
      },
    );
  }

  CapabilityExecutionResult switchWorkspace({
    required Map<String, Object?> arguments,
    required List<AgentWorkspace>? workspaces,
  }) {
    final workspaceList = workspaces;
    if (workspaceList == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'workspace.switch',
        output: {'ok': false, 'error': 'workspace store unavailable'},
      );
    }

    final rawWorkspaceId = arguments['workspace_id'];
    final rawName = arguments['name'];
    final workspaceId = rawWorkspaceId is String ? rawWorkspaceId.trim() : '';
    final name = rawName is String ? rawName.trim() : '';
    if (workspaceId.isEmpty && name.isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'workspace.switch',
        output: {'ok': false, 'error': 'workspace_id or name is required'},
      );
    }

    final matches = workspaceList
        .where((workspace) {
          if (workspaceId.isNotEmpty) {
            return workspace.id == workspaceId;
          }
          return workspace.name == name;
        })
        .toList(growable: false);
    if (matches.isEmpty) {
      return CapabilityExecutionResult(
        capabilityId: 'workspace.switch',
        output: {
          'ok': false,
          'error': 'workspace not found',
          if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
          if (name.isNotEmpty) 'name': name,
        },
      );
    }

    final workspace = matches.first;
    return CapabilityExecutionResult(
      capabilityId: 'workspace.switch',
      output: {
        'ok': true,
        'workspaceId': workspace.id,
        'activeWorkspaceId': workspace.id,
        'name': workspace.name,
        'description': workspace.description,
      },
    );
  }
}
