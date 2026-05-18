import 'package:flutter/material.dart';

import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/files/app_file_store.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/permissions/permission_policy.dart';
import 'workbench_panel.dart';

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
    return WorkbenchPanel(
      title: 'Runtime',
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Artifact', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final artifact in artifacts)
            InfoRow(
              icon: artifact.type == ArtifactType.webApp
                  ? Icons.web_asset
                  : Icons.inventory_2_outlined,
              title: artifact.title,
              body: '${artifact.type.label} · ${artifact.summary}',
              onTap: artifact.type == ArtifactType.webApp
                  ? () => onOpenWebApp(artifact)
                  : null,
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workspace Files',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '刷新文件列表',
                icon: const Icon(Icons.refresh),
                onPressed: onRefreshFiles,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (files.isEmpty)
            const InfoRow(
              icon: Icons.folder_open_outlined,
              title: '暂无文件',
              body: 'AI 通过 file.write_app_file 写入的工作区文件会出现在这里。',
            )
          else
            for (final file in files)
              InfoRow(
                icon: Icons.insert_drive_file_outlined,
                title: file.path,
                body:
                    '${_formatBytes(file.bytes)} · ${_formatModified(file.modifiedAt)} · 点击预览/导出',
                onTap: () => onOpenFile(file),
              ),
          const SizedBox(height: 16),
          Text('Note', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (notes.isEmpty)
            const InfoRow(
              icon: Icons.note_alt_outlined,
              title: '暂无 Note',
              body: 'AI 可以通过 db.note.create 写入当前 Workspace 的本地 Note。',
            )
          else
            for (final note in notes)
              InfoRow(
                icon: Icons.note_alt_outlined,
                title: note.title,
                body: note.content,
              ),
          const SizedBox(height: 16),
          Text(
            'Capability Registry',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final capability in capabilities)
            _CapabilityRow(
              capability: capability,
              decision: policy.decide(capability),
            ),
        ],
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
