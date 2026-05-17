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

class _MobileWorkbench extends StatefulWidget {
  const _MobileWorkbench({
    required this.workspacePanel,
    required this.chatPanel,
    required this.runtimePanel,
  });

  final Widget workspacePanel;
  final Widget chatPanel;
  final Widget runtimePanel;

  @override
  State<_MobileWorkbench> createState() => _MobileWorkbenchState();
}

class _MobileWorkbenchState extends State<_MobileWorkbench> {
  int _index = 1;

  @override
  Widget build(BuildContext context) {
    final pages = [
      widget.workspacePanel,
      widget.chatPanel,
      widget.runtimePanel,
    ];
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: pages[_index],
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: keyboardVisible
            ? const SizedBox.shrink()
            : NavigationBar(
                selectedIndex: _index,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.workspaces),
                    label: '空间',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    label: '对话',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.hub_outlined),
                    label: '运行时',
                  ),
                ],
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
              ),
      ),
    );
  }
}
