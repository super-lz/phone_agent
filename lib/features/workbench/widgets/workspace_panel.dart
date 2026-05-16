import 'package:flutter/material.dart';

import '../../../domain/memory/memory.dart';
import '../../../domain/workspace/workspace.dart';
import 'workbench_panel.dart';

class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({
    required this.workspaces,
    required this.selectedWorkspaceId,
    required this.visibleMemories,
    required this.onCreateWorkspace,
    required this.onSelectWorkspace,
    super.key,
  });

  final List<AgentWorkspace> workspaces;
  final String selectedWorkspaceId;
  final List<AgentMemory> visibleMemories;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<String> onSelectWorkspace;

  @override
  Widget build(BuildContext context) {
    return WorkbenchPanel(
      title: 'Workspace',
      trailing: IconButton(
        tooltip: '创建工作区',
        icon: const Icon(Icons.add),
        onPressed: onCreateWorkspace,
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final workspace in workspaces)
            _WorkspaceTile(
              workspace: workspace,
              selected: workspace.id == selectedWorkspaceId,
              onTap: () => onSelectWorkspace(workspace.id),
            ),
          const SizedBox(height: 16),
          Text('可见记忆', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final memory in visibleMemories)
            InfoRow(
              icon: Icons.memory,
              title: memory.scope.label,
              body: memory.content,
            ),
        ],
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.selected,
    required this.onTap,
  });

  final AgentWorkspace workspace;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: const Icon(Icons.folder_open),
      title: Text(workspace.name),
      subtitle: Text(
        workspace.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}
