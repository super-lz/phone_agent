import 'package:flutter/material.dart';

import '../../../domain/workspace/workspace.dart';

class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({required this.workspace, super.key});

  final AgentWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.workspaces_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspace.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  workspace.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
