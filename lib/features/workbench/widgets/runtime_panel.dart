import 'package:flutter/material.dart';

import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/files/app_file_store.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/permissions/permission_policy.dart';

class RuntimePanel extends StatelessWidget {
  const RuntimePanel({
    required this.artifacts,
    required this.files,
    required this.notes,
    required this.capabilities,
    required this.permissionMode,
    required this.onOpenWebApp,
    required this.onOpenFile,
    required this.onRefreshFiles,
    super.key,
  });

  final List<AgentArtifact> artifacts;
  final List<AppFileEntry> files;
  final List<AgentNote> notes;
  final List<CapabilityDefinition> capabilities;
  final PermissionMode permissionMode;
  final ValueChanged<AgentArtifact> onOpenWebApp;
  final ValueChanged<AppFileEntry> onOpenFile;
  final VoidCallback onRefreshFiles;

  @override
  Widget build(BuildContext context) {
    final policy = PermissionPolicy(permissionMode);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
            ...artifacts.map((artifact) => _buildArtifactTile(context, artifact)),
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            '工作区文件',
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.refresh_rounded, size: 20, color: colorScheme.primary),
              onPressed: onRefreshFiles,
            ),
          ),
          if (files.isEmpty)
            _buildEmptyState(Icons.folder_open_outlined, '暂无沙箱文件')
          else
            ...files.map((file) => _buildFileTile(context, file)),
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
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Column(
                    children: capabilities
                        .map((c) => _CapabilityRow(
                              capability: c,
                              decision: policy.decide(c),
                            ))
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

  Widget _buildSectionHeader(BuildContext context, String title,
      {Widget? trailing}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactTile(BuildContext context, AgentArtifact artifact) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -1),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            artifact.type == ArtifactType.webApp
                ? Icons.web_rounded
                : artifact.type == ArtifactType.location
                ? Icons.location_on_rounded
                : Icons.insert_drive_file_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          artifact.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${artifact.type.label} · ${artifact.summary}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: artifact.type == ArtifactType.webApp
            ? () => onOpenWebApp(artifact)
            : null,
      ),
    );
  }

  Widget _buildFileTile(BuildContext context, AppFileEntry file) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -1),
        leading: const Icon(Icons.description_outlined, color: Colors.blueGrey, size: 22),
        title: Text(
          file.path,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${_formatBytes(file.bytes)} · ${_formatModified(file.modifiedAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () => onOpenFile(file),
      ),
    );
  }

  Widget _buildNoteTile(BuildContext context, AgentNote note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        visualDensity: const VisualDensity(vertical: -1),
        leading: const Icon(Icons.sticky_note_2_outlined, color: Colors.amber, size: 22),
        title: Text(
          note.title.isEmpty ? '未命名笔记' : note.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          note.content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kib = bytes / 1024;
    if (kib < 1024) {
      return '${kib.toStringAsFixed(1)} KB';
    }
    return '${(kib / 1024).toStringAsFixed(1)} MB';
  }

  String _formatModified(DateTime modifiedAt) {
    final local = modifiedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6ECE3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
