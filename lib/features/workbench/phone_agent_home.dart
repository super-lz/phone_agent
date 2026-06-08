import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

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
import '../../domain/workbench/workbench_store.dart';
import '../settings/model_settings_page.dart';
import '../settings/permission_settings_page.dart';
import '../web_app_runtime/web_app_runtime_page.dart';
import 'audit_log_page.dart';
import 'controllers/workbench_controller.dart';
import 'widgets/chat_panel.dart';
import 'widgets/file_preview_page.dart';
import 'widgets/local_data_clear_dialog.dart';
import 'widgets/memory_editor_dialog.dart';
import 'widgets/mobile_drawer_sections.dart';
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

class _PhoneAgentHomeState extends State<PhoneAgentHome>
    with WidgetsBindingObserver {
  late final WorkbenchController _controller;
  late final ModelApiKeyStore _apiKeyStore;
  late final ModelSettingsStore _modelSettingsStore;
  late final AppPermissionService _permissionService;
  final _composerController = TextEditingController();
  final List<MessageBlock> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setAppInForeground(state == AppLifecycleState.resumed);
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

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }
      final size = await photo.length();
      final block = MessageBlock.image(
        name: photo.name,
        uri: Uri.file(photo.path).toString(),
        bytes: size,
        mimeType: _imageMimeType(photo.path.split('.').last),
      );
      setState(() {
        _pendingAttachments.add(block);
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍照失败：$error')));
    }
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
    final content = await showDialog<String>(
      context: context,
      builder: (context) => MemoryEditorDialog(memory: memory),
    );

    if (content == null) {
      return;
    }
    if (memory == null) {
      _controller.createMemory(content: content);
      return;
    }
    _controller.updateMemory(memoryId: memory.id, content: content);
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
      WebAppRuntimeRoute(
        webApp: webApp,
        callCapability: _controller.callCapabilityFromWebApp,
        readResource: _controller.readWebAppResource,
        runtimeLogWriter: _controller.recordWebAppRuntimeLog,
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
      final extension = entry.path.split('.').last.toLowerCase();
      final isOfficeOrPdf = const {
        'pdf',
        'docx',
        'xlsx',
        'pptx',
      }.contains(extension);
      final isImage = const {
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
        'heic',
      }.contains(extension);

      if (isOfficeOrPdf) {
        final filePath = entry.uri.toFilePath();
        try {
          final result = await OpenFilex.open(filePath);
          if (result.type == ResultType.done) {
            return;
          }
        } catch (_) {}
      }

      if (isImage) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => FilePreviewPage(
              entry: entry,
              content: '', // Images don't need text content
            ),
          ),
        );
        return;
      }

      // Only read as text if it's not a known binary format
      final content = await _controller.readWorkspaceFile(entry);
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              FilePreviewPage(entry: entry, content: content.content),
        ),
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

  Future<void> _confirmClearLocalData() async {
    if (_controller.isSending) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复生成中，稍后再清理。')));
      return;
    }
    final confirmed = await showLocalDataClearDialog(context);
    if (confirmed != true) {
      return;
    }
    try {
      await _controller.clearLocalWorkspaceData();
      if (!mounted) {
        return;
      }
      setState(_pendingAttachments.clear);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地工作区内容已清理。')));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 1000;
        final theme = Theme.of(context);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_controller.currentWorkspace.name),
                Text(
                  _controller.workspaceId == 'default' ? '默认工作区' : '当前工作区',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            leading: isMobile
                ? Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  )
                : null,
            actions: [
              if (isMobile)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: '资源与运行时',
                    icon: const Icon(Icons.hub_outlined),
                    onPressed: () {
                      unawaited(_controller.refreshWorkspaceFiles());
                      Scaffold.of(context).openEndDrawer();
                    },
                  ),
                ),
              if (!isMobile) ...[
                IconButton(
                  tooltip: '清理本地数据',
                  icon: const Icon(Icons.cleaning_services_outlined),
                  onPressed: _confirmClearLocalData,
                ),
                IconButton(
                  tooltip: '审计日志',
                  icon: const Icon(Icons.history_outlined),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => AuditLogPage(
                          workbenchStore: widget.workbenchStore!,
                        ),
                      ),
                    );
                  },
                ),
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
              ],
              const SizedBox(width: 8),
            ],
          ),
          drawer: isMobile
              ? Drawer(
                  child: Column(
                    children: [
                      const MobileDrawerHeader(),
                      Expanded(
                        child: WorkspacePanel(
                          workspaces: _controller.workspaces,
                          selectedWorkspaceId: _controller.workspaceId,
                          visibleMemories: _controller.visibleMemories,
                          onCreateWorkspace: _controller.createWorkspace,
                          onSelectWorkspace: (id) {
                            _controller.setWorkspace(id);
                            Navigator.pop(context);
                          },
                          onCreateMemory: _openMemoryEditor,
                          onEditMemory: _openMemoryEditor,
                          onDeleteMemory: _confirmDeleteMemory,
                        ),
                      ),
                      const Divider(),
                      MobileDrawerFooter(
                        workbenchStore: widget.workbenchStore,
                        permissionService: _permissionService,
                        apiKeyStore: _apiKeyStore,
                        modelSettingsStore: _modelSettingsStore,
                        onClearLocalData: _confirmClearLocalData,
                      ),
                    ],
                  ),
                )
              : null,
          endDrawer: isMobile
              ? Drawer(
                  width: MediaQuery.of(context).size.width * 0.85,
                  child: RuntimePanel(
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
                )
              : null,
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
              currentRun: _controller.currentRun,
              onSendPrompt: _sendPrompt,
              onCancelRun: _controller.cancelCurrentRun,
              onOpenWebAppArtifact: _openWebAppArtifact,
              onApproveCapability: _controller.approveCapabilityRequest,
              onDenyCapability: _controller.denyCapabilityRequest,
              pendingAttachments: List.unmodifiable(_pendingAttachments),
              onAddFile: _pickFileAttachment,
              onAddImage: _pickImageAttachment,
              onTakePhoto: _takePhoto,
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
      },
    );
  }
}
