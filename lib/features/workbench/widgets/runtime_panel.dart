import 'package:flutter/material.dart';

import '../../../domain/artifacts/artifact.dart';
import '../../../domain/capabilities/capability.dart';
import '../../../domain/notes/note.dart';
import '../../../domain/permissions/permission_policy.dart';
import 'workbench_panel.dart';

class RuntimePanel extends StatelessWidget {
  const RuntimePanel({
    required this.artifacts,
    required this.notes,
    required this.capabilities,
    required this.permissionMode,
    required this.onOpenWebApp,
    super.key,
  });

  final List<AgentArtifact> artifacts;
  final List<AgentNote> notes;
  final List<CapabilityDefinition> capabilities;
  final PermissionMode permissionMode;
  final ValueChanged<AgentArtifact> onOpenWebApp;

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
