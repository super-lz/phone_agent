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
    required this.onCreateMemory,
    required this.onEditMemory,
    required this.onDeleteMemory,
    super.key,
  });

  final List<AgentWorkspace> workspaces;
  final String selectedWorkspaceId;
  final List<AgentMemory> visibleMemories;
  final VoidCallback onCreateWorkspace;
  final ValueChanged<String> onSelectWorkspace;
  final VoidCallback onCreateMemory;
  final ValueChanged<AgentMemory> onEditMemory;
  final ValueChanged<AgentMemory> onDeleteMemory;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  '长期记忆',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '新增记忆',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onCreateMemory,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibleMemories.isEmpty)
            const InfoRow(
              icon: Icons.memory,
              title: '暂无记忆',
              body: '长期记忆会在所有 Workspace 中自动作为上下文使用。',
            )
          else
            for (final memory in visibleMemories)
              _MemoryTile(
                memory: memory,
                onEdit: () => onEditMemory(memory),
                onDelete: () => onDeleteMemory(memory),
              ),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.memory,
    required this.onEdit,
    required this.onDelete,
  });

  final AgentMemory memory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.memory),
        title: const Text('长期记忆'),
        subtitle: Text(memory.content),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '编辑记忆',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: '删除记忆',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
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
