import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../settings/model_settings_page.dart';
import 'controllers/workbench_controller.dart';
import 'widgets/chat_panel.dart';
import 'widgets/runtime_panel.dart';
import 'widgets/workbench_shell.dart';
import 'widgets/workspace_panel.dart';

class PhoneAgentHome extends StatefulWidget {
  const PhoneAgentHome({this.noteStore, this.fileStore, super.key});

  final AgentNoteStore? noteStore;
  final AppFileStore? fileStore;

  @override
  State<PhoneAgentHome> createState() => _PhoneAgentHomeState();
}

class _PhoneAgentHomeState extends State<PhoneAgentHome> {
  late final WorkbenchController _controller;
  final _composerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = WorkbenchController(
      noteStore: widget.noteStore,
      fileStore: widget.fileStore,
    );
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
    unawaited(_controller.sendPrompt(prompt));
  }

  Future<void> _openMemoryEditor([AgentMemory? memory]) async {
    final result = await showDialog<_MemoryEditorResult>(
      context: context,
      builder: (context) => _MemoryEditorDialog(memory: memory),
    );

    if (result == null) {
      return;
    }
    if (memory == null) {
      _controller.createMemory(content: result.content);
      return;
    }
    _controller.updateMemory(memoryId: memory.id, content: result.content);
  }

  Future<void> _confirmDeleteMemory(AgentMemory memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除记忆'),
          content: Text('确定忘记这条长期记忆吗？\n\n${memory.content}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _controller.deleteMemory(memory.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Phone Agent'),
        actions: [
          IconButton(
            tooltip: '模型设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ModelSettingsPage(),
                ),
              );
            },
          ),
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
          onCreateMemory: _openMemoryEditor,
          onEditMemory: _openMemoryEditor,
          onDeleteMemory: _confirmDeleteMemory,
        ),
        chatPanel: ChatPanel(
          workspace: _controller.currentWorkspace,
          messages: _controller.messages,
          composerController: _composerController,
          isSending: _controller.isSending,
          onSendPrompt: _sendPrompt,
        ),
        runtimePanel: RuntimePanel(
          artifacts: _controller.workspaceArtifacts,
          notes: _controller.workspaceNotes,
          capabilities: _controller.capabilities,
          permissionMode: _controller.permissionMode,
        ),
      ),
    );
  }
}

class _MemoryEditorResult {
  const _MemoryEditorResult({required this.content});

  final String content;
}

class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({this.memory});

  final AgentMemory? memory;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    final memory = widget.memory;
    _textController = TextEditingController(text: memory?.content ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.memory == null ? '新增记忆' : '编辑记忆'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '长期记忆会在所有 Workspace 中自动作为上下文使用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            minLines: 3,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '记忆内容',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(
              context,
            ).pop(_MemoryEditorResult(content: _textController.text));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
