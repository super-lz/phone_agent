import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/files/app_file_store.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/permissions/permission_policy.dart';
import 'file_size_format.dart';

class RuntimePanel extends StatelessWidget {
  const RuntimePanel({
    required this.artifacts,
    required this.files,
    required this.notes,
    required this.capabilities,
    required this.permissionMode,
    required this.onOpenWebApp,
    required this.onOpenFileManager,
    required this.onRefreshFiles,
    super.key,
  });

  final List<AgentArtifact> artifacts;
  final List<AppFileEntry> files;
  final List<AgentNote> notes;
  final List<CapabilityDefinition> capabilities;
  final PermissionMode permissionMode;
  final ValueChanged<AgentArtifact> onOpenWebApp;
  final VoidCallback onOpenFileManager;
  final VoidCallback onRefreshFiles;

  @override
  Widget build(BuildContext context) {
    final policy = PermissionPolicy(permissionMode);
    final theme = Theme.of(context);
    final colors = context.phoneAgentColors;

    return Scaffold(
      backgroundColor: colors.panelBackground,
      appBar: AppBar(
        title: const Text('资源与运行时'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader(context, '应用与产物 (Artifacts)'),
          if (artifacts.isEmpty)
            _buildEmptyState(Icons.inventory_2_outlined, '当前工作区暂无产物')
          else
            ...artifacts.map(
              (artifact) => _buildArtifactTile(context, artifact),
            ),
          const SizedBox(height: 24),
          _buildSectionHeader(context, '工作区文件'),
          _buildFileManagerEntry(context),
          const SizedBox(height: 24),
          _buildSectionHeader(context, '备忘录 (Notes)'),
          if (notes.isEmpty)
            _buildEmptyState(Icons.note_alt_outlined, '暂无工作笔记')
          else
            ...notes.map((note) => _buildNoteTile(context, note)),
          const SizedBox(height: 24),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '能力注册表 (Capabilities)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Column(
                    children: capabilities
                        .map(
                          (c) => _CapabilityRow(
                            capability: c,
                            decision: policy.decide(c),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildFileManagerEntry(BuildContext context) {
    final colors = context.phoneAgentColors;
    final directoryCount = files
        .map((file) => file.path.split('/').first)
        .where((segment) => segment.isNotEmpty)
        .toSet()
        .length;
    final totalBytes = files.fold<int>(0, (sum, file) => sum + file.bytes);
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpenFileManager,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                color: colors.primaryAction,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '打开文件管理器',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      files.isEmpty
                          ? '当前工作区暂无文件'
                          : '${files.length} 个文件 · $directoryCount 个顶层目录 · ${_formatBytes(totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: colors.textSecondary,
                onPressed: onRefreshFiles,
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.phoneAgentColors.textPrimary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String label) {
    return Builder(
      builder: (context) {
        final colors = context.phoneAgentColors;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.textTertiary),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtifactTile(BuildContext context, AgentArtifact artifact) {
    final colors = context.phoneAgentColors;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -1),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.cardSelectedBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            artifact.type == ArtifactType.webApp
                ? Icons.web_rounded
                : artifact.type == ArtifactType.location
                ? Icons.location_on_rounded
                : Icons.insert_drive_file_rounded,
            color: colors.primaryAction,
            size: 20,
          ),
        ),
        title: Text(
          artifact.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${artifact.type.label} · ${artifact.summary}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        onTap: artifact.type == ArtifactType.webApp
            ? () => onOpenWebApp(artifact)
            : null,
      ),
    );
  }

  Widget _buildNoteTile(BuildContext context, AgentNote note) {
    final colors = context.phoneAgentColors;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(
          Icons.sticky_note_2_outlined,
          color: colors.primaryAction,
          size: 22,
        ),
        title: Text(
          note.title.isEmpty ? '未命名笔记' : note.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Text(
          note.content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) => formatFileSize(bytes);
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.capability, required this.decision});

  final CapabilityDefinition capability;
  final PermissionDecision decision;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              capability.id,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          _RuntimeBadge(label: capability.risk.name),
          const SizedBox(width: 6),
          _RuntimeBadge(label: decision.name),
        ],
      ),
    );
  }
}

class _RuntimeBadge extends StatelessWidget {
  const _RuntimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSelectedBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.statusText),
        ),
      ),
    );
  }
}
