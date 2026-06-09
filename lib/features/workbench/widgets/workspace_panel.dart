import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
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
    final colors = context.phoneAgentColors;
    return WorkbenchPanel(
      title: '工作区与上下文',
      trailing: IconButton(
        tooltip: '新建工作区',
        icon: const Icon(Icons.create_new_folder_outlined, size: 22),
        onPressed: onCreateWorkspace,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
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
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
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
    final colors = context.phoneAgentColors;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: colors.primaryAction,
              ),
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
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '编辑记忆',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '删除记忆',
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
    final colors = context.phoneAgentColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? colors.cardSelectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        selected: selected,
        leading: Icon(
          selected ? Icons.folder_rounded : Icons.folder_outlined,
          color: selected ? colors.primaryAction : colors.textSecondary,
        ),
        title: Text(
          workspace.name,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.primaryAction : colors.textPrimary,
          ),
        ),
        subtitle: Text(
          workspace.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? colors.primaryAction.withValues(alpha: 0.74)
                : colors.textSecondary,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: onTap,
        visualDensity: const VisualDensity(vertical: -1),
      ),
    );
  }
}
