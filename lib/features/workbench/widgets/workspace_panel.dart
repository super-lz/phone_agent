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
    final theme = Theme.of(context);
    return WorkbenchPanel(
      title: '工作区与上下文',
      trailing: IconButton(
        tooltip: '新建工作区',
        icon: const Icon(Icons.create_new_folder_outlined, size: 22),
        onPressed: onCreateWorkspace,
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final workspace in workspaces)
            _WorkspaceTile(
              workspace: workspace,
              selected: workspace.id == selectedWorkspaceId,
              onTap: () => onSelectWorkspace(workspace.id),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '长期记忆',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '新增记忆',
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: onCreateMemory,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (visibleMemories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: InfoRow(
                icon: Icons.lightbulb_outline,
                title: '还没有长期记忆',
                body: 'AI 会自动记住跨工作区的偏好和重要事实，通过对话或手动添加。',
              ),
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                ),
              ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        selected: selected,
        leading: Icon(
          selected ? Icons.folder_rounded : Icons.folder_outlined,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          workspace.name,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          workspace.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: selected ? colorScheme.primary.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        visualDensity: const VisualDensity(vertical: -1),
      ),
    );
  }
}
