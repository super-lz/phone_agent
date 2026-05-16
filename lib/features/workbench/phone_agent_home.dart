import 'package:flutter/material.dart';

import '../../domain/permissions/permission_policy.dart';
import 'controllers/workbench_controller.dart';
import 'widgets/chat_panel.dart';
import 'widgets/runtime_panel.dart';
import 'widgets/workbench_shell.dart';
import 'widgets/workspace_panel.dart';

class PhoneAgentHome extends StatefulWidget {
  const PhoneAgentHome({super.key});

  @override
  State<PhoneAgentHome> createState() => _PhoneAgentHomeState();
}

class _PhoneAgentHomeState extends State<PhoneAgentHome> {
  late final WorkbenchController _controller;
  final _composerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = WorkbenchController();
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _sendPrompt() {
    final prompt = _composerController.text.trim();
    if (prompt.isEmpty) {
      return;
    }
    _composerController.clear();
    _controller.sendPrompt(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Agent'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton(
              value: _controller.permissionMode,
              items: _controller.permissionModes
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: _controller.setPermissionMode,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: WorkbenchShell(
        workspacePanel: WorkspacePanel(
          workspaces: _controller.workspaces,
          selectedWorkspaceId: _controller.workspaceId,
          visibleMemories: _controller.visibleMemories,
          onCreateWorkspace: _controller.createWorkspace,
          onSelectWorkspace: _controller.setWorkspace,
        ),
        chatPanel: ChatPanel(
          workspace: _controller.currentWorkspace,
          messages: _controller.messages,
          composerController: _composerController,
          onSendPrompt: _sendPrompt,
        ),
        runtimePanel: RuntimePanel(
          artifacts: _controller.workspaceArtifacts,
          capabilities: _controller.capabilities,
          permissionMode: _controller.permissionMode,
        ),
      ),
    );
  }
}
