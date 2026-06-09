import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

class WorkbenchShell extends StatelessWidget {
  const WorkbenchShell({
    required this.workspacePanel,
    required this.chatPanel,
    required this.runtimePanel,
    super.key,
  });

  final Widget workspacePanel;
  final Widget chatPanel;
  final Widget runtimePanel;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return ColoredBox(
            color: colors.pageBackground,
            child: _MobileWorkbench(
              workspacePanel: workspacePanel,
              chatPanel: chatPanel,
              runtimePanel: runtimePanel,
            ),
          );
        }

        return ColoredBox(
          color: colors.pageBackground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                SizedBox(width: 280, child: _PanelFrame(child: workspacePanel)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _PanelFrame(child: chatPanel)),
                const SizedBox(width: 10),
                SizedBox(width: 340, child: _PanelFrame(child: runtimePanel)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileWorkbench extends StatelessWidget {
  const _MobileWorkbench({
    required this.workspacePanel,
    required this.chatPanel,
    required this.runtimePanel,
  });

  final Widget workspacePanel;
  final Widget chatPanel;
  final Widget runtimePanel;

  @override
  Widget build(BuildContext context) {
    return chatPanel;
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panelBackground,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      ),
    );
  }
}
