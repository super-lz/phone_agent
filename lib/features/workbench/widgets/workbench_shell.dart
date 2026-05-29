import 'package:flutter/material.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return _MobileWorkbench(
            workspacePanel: workspacePanel,
            chatPanel: chatPanel,
            runtimePanel: runtimePanel,
          );
        }

        return Row(
          children: [
            SizedBox(width: 280, child: workspacePanel),
            const VerticalDivider(width: 1),
            Expanded(flex: 2, child: chatPanel),
            const VerticalDivider(width: 1),
            SizedBox(width: 340, child: runtimePanel),
          ],
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
