import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/capabilities/capability_runtime.dart';
import '../../data/models/model_api_key_store.dart';
import '../../data/models/model_settings_store.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../data/permissions/app_permission_service.dart';
import '../../domain/artifacts/artifact.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/files/app_file_store.dart';
import '../../domain/memory/memory.dart';
import '../../domain/notes/note_store.dart';
import '../../domain/permissions/permission_policy.dart';
import '../../domain/workbench/workbench_store.dart';
import '../settings/model_settings_page.dart';
import '../settings/permission_settings_page.dart';
import '../web_app_runtime/web_app_runtime_page.dart';
import 'controllers/workbench_controller.dart';
import 'widgets/chat_panel.dart';
import 'widgets/runtime_panel.dart';
import 'widgets/workbench_shell.dart';
import 'widgets/workspace_panel.dart';

class PhoneAgentHome extends StatefulWidget {
  const PhoneAgentHome({
    this.apiKeyStore,
    this.chatClient,
    this.capabilityRuntime,
    this.modelSettingsStore,
    this.noteStore,
    this.fileStore,
    this.workbenchStore,
    super.key,
  });

  final ModelApiKeyStore? apiKeyStore;
  final OpenAiCompatibleChatClient? chatClient;
  final CapabilityRuntime? capabilityRuntime;
  final ModelSettingsStore? modelSettingsStore;
  final AgentNoteStore? noteStore;
  final AppFileStore? fileStore;
  final WorkbenchStore? workbenchStore;

  @override
  State<PhoneAgentHome> createState() => _PhoneAgentHomeState();
}

class _PhoneAgentHomeState extends State<PhoneAgentHome> {
  late final WorkbenchController _controller;
  late final ModelApiKeyStore _apiKeyStore;
  late final ModelSettingsStore _modelSettingsStore;
  late final AppPermissionService _permissionService;
  final _composerController = TextEditingController();
  final List<MessageBlock> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _apiKeyStore = widget.apiKeyStore ?? ModelApiKeyStore();
    _modelSettingsStore =
        widget.modelSettingsStore ?? InMemoryModelSettingsStore();
    _permissionService = const AppPermissionService();
    _controller = WorkbenchController(
      apiKeyStore: _apiKeyStore,
      chatClient: widget.chatClient,
      capabilityRuntime: widget.capabilityRuntime,
      modelSettingsStore: _modelSettingsStore,
      noteStore: widget.noteStore,
      fileStore: widget.fileStore,
      workbenchStore: widget.workbenchStore,
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
    if (prompt.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }
    final messageText = prompt.isEmpty ? '请处理这些附件。' : prompt;
    final attachments = List<MessageBlock>.unmodifiable(_pendingAttachments);
    _composerController.clear();
    setState(_pendingAttachments.clear);
    unawaited(_controller.sendPrompt(messageText, attachments: attachments));
  }

  Future<void> _pickFileAttachment() async {
    await _pickAttachment(type: FileType.any);
  }

  Future<void> _pickImageAttachment() async {
    await _pickAttachment(type: FileType.image);
  }

  Future<void> _pickAttachment({required FileType type}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final blocks = result.files.map((file) {
        final uri = _uriForPickedFile(file);
        if (type == FileType.image) {
          return MessageBlock.image(
            name: file.name,
            uri: uri,
            bytes: file.size,
            mimeType: _imageMimeType(file.extension),
          );
        }
        return MessageBlock.fileAttachment(
          name: file.name,
          uri: uri,
          bytes: file.size,
          extension: file.extension,
        );
      });
      setState(() {
        _pendingAttachments.addAll(blocks);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择附件失败：$error')));
    }
  }

  String _uriForPickedFile(PlatformFile file) {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return Uri.file(path).toString();
    }
    return file.identifier ?? file.name;
  }

  String? _imageMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return null;
    }
  }

  void _removePendingAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) {
      return;
    }
    setState(() {
      _pendingAttachments.removeAt(index);
    });
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

  void _openWebApp(AgentArtifact webApp) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WebAppRuntimePage(
          webApp: webApp,
          callCapability: _controller.callCapabilityFromWebApp,
          readResource: _controller.readWebAppResource,
          runtimeLogWriter: _controller.recordWebAppRuntimeLog,
        ),
      ),
    );
  }

  void _openWebAppArtifact(String artifactId) {
    final artifact = _controller.artifactById(artifactId);
    if (artifact == null || artifact.type != ArtifactType.webApp) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('找不到可预览的 Web App')));
      return;
    }
    _openWebApp(artifact);
  }

  Future<void> _openWorkspaceFile(AppFileEntry entry) async {
    try {
      final content = await _controller.readWorkspaceFile(entry);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(entry.path),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  content.content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _shareWorkspaceFile(entry),
                icon: const Icon(Icons.ios_share),
                label: const Text('分享'),
              ),
              TextButton.icon(
                onPressed: () => _saveWorkspaceFile(entry),
                icon: const Icon(Icons.save_alt),
                label: const Text('另存'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开文件失败：$error')));
    }
  }

  Future<void> _shareWorkspaceFile(AppFileEntry entry) async {
    try {
      final content = await _controller.readWorkspaceFile(entry);
      final bytes = Uint8List.fromList(utf8.encode(content.content));
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: _fileName(entry.path),
            mimeType: _mimeTypeForWorkspaceFile(entry.path),
          ),
        ],
        subject: entry.path,
        fileNameOverrides: [_fileName(entry.path)],
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享文件失败：$error')));
    }
  }

  Future<void> _saveWorkspaceFile(AppFileEntry entry) async {
    try {
      final content = await _controller.readWorkspaceFile(entry);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存工作区文件',
        fileName: _fileName(entry.path),
        bytes: Uint8List.fromList(utf8.encode(content.content)),
        type: FileType.any,
      );
      if (!mounted || path == null) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存到：$path')));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存文件失败：$error')));
    }
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  String _mimeTypeForWorkspaceFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html';
    }
    if (lower.endsWith('.md')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.json')) {
      return 'application/json';
    }
    if (lower.endsWith('.csv')) {
      return 'text/csv';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'text/plain';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Phone Agent'),
        actions: [
          IconButton(
            tooltip: '权限管理',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => PermissionSettingsPage(
                    permissionService: _permissionService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '模型设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ModelSettingsPage(
                    apiKeyStore: _apiKeyStore,
                    modelSettingsStore: _modelSettingsStore,
                  ),
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
          onOpenWebAppArtifact: _openWebAppArtifact,
          onApproveCapability: _controller.approveCapabilityRequest,
          onDenyCapability: _controller.denyCapabilityRequest,
          pendingAttachments: List.unmodifiable(_pendingAttachments),
          onAddFile: _pickFileAttachment,
          onAddImage: _pickImageAttachment,
          onRemovePendingAttachment: _removePendingAttachment,
        ),
        runtimePanel: RuntimePanel(
          artifacts: _controller.workspaceArtifacts,
          files: _controller.workspaceFiles,
          notes: _controller.workspaceNotes,
          capabilities: _controller.capabilities,
          permissionMode: _controller.permissionMode,
          onOpenWebApp: _openWebApp,
          onOpenFile: _openWorkspaceFile,
          onRefreshFiles: () {
            unawaited(_controller.refreshWorkspaceFiles());
          },
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
