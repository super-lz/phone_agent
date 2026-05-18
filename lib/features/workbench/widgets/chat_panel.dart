import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/conversation/message_block.dart';
import '../../../domain/workspace/workspace.dart';
import 'message_view.dart';
import 'workspace_header.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.workspace,
    required this.messages,
    required this.composerController,
    required this.isSending,
    required this.onSendPrompt,
    required this.onOpenWebAppArtifact,
    required this.onApproveCapability,
    required this.onDenyCapability,
    required this.pendingAttachments,
    required this.onAddFile,
    required this.onAddImage,
    required this.onRemovePendingAttachment,
    super.key,
  });

  final AgentWorkspace workspace;
  final List<AgentMessage> messages;
  final TextEditingController composerController;
  final bool isSending;
  final VoidCallback onSendPrompt;
  final ValueChanged<String> onOpenWebAppArtifact;
  final ValueChanged<Map<String, Object?>> onApproveCapability;
  final ValueChanged<Map<String, Object?>> onDenyCapability;
  final List<MessageBlock> pendingAttachments;
  final VoidCallback onAddFile;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemovePendingAttachment;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  static const double _nearBottomDistance = 80;
  static const double _showScrollToBottomDistance = 360;
  static const double _scrollLockDistance = 120;
  static const double _scrollLockDragExtent = 48;
  static const double _loadOlderDistance = 56;
  static const int _initialMessagePageSize = 32;
  static const int _messagePageSize = 24;

  final _scrollController = ScrollController();
  bool _autoScrollEnabled = true;
  bool _userScrollLocked = false;
  bool _userIsDragging = false;
  bool _showScrollToBottom = false;
  bool _isLoadingOlderMessages = false;
  double _userAwayDragExtent = 0;
  int _visibleMessageCount = _initialMessagePageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollPositionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomNow());
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.id != widget.workspace.id) {
      _visibleMessageCount = _initialMessagePageSize;
      _unlockAutoScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomNow());
      return;
    }
    final totalDisplayMessages = _coalesceAssistantMessages(
      widget.messages,
    ).length;
    if (_visibleMessageCount > totalDisplayMessages) {
      _visibleMessageCount = totalDisplayMessages < _initialMessagePageSize
          ? _initialMessagePageSize
          : totalDisplayMessages;
    }
    if (_startsNewUserTurn(oldWidget)) {
      _unlockAutoScroll();
    }
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.isSending != widget.isSending ||
        _lastMessageData(oldWidget) != _lastMessageData(widget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_shouldAutoScrollForUpdate()) {
          _scrollToBottom();
        } else {
          _updateScrollToBottomVisibility();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScrollPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScrollPositionChanged() {
    if (_isNearTop()) {
      _loadOlderMessages();
    }
    _updateScrollToBottomVisibility();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController
        .animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (mounted) {
            _updateScrollToBottomVisibility();
          }
        });
  }

  void _jumpToBottomNow() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(0);
    _updateScrollToBottomVisibility();
  }

  bool _isNearBottom() {
    return _distanceToBottom() < _nearBottomDistance;
  }

  double _distanceToBottom() {
    if (!_scrollController.hasClients) {
      return 0;
    }
    return _scrollController.position.pixels;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userIsDragging = true;
      _autoScrollEnabled = false;
      _userAwayDragExtent = 0;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _autoScrollEnabled = false;
      _userAwayDragExtent += (notification.scrollDelta ?? 0).abs();
      if (_isNearTop()) {
        _loadOlderMessages();
      }
      if (_distanceToBottom() > _scrollLockDistance ||
          _userAwayDragExtent > _scrollLockDragExtent) {
        _lockAutoScroll();
      }
    }
    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.forward:
          _autoScrollEnabled = false;
        case ScrollDirection.reverse:
        case ScrollDirection.idle:
          if (_isNearBottom() && !_userIsDragging) {
            _unlockAutoScroll();
          }
      }
    }
    if (notification is ScrollEndNotification) {
      _userIsDragging = false;
      _userAwayDragExtent = 0;
      if (_isNearTop()) {
        _loadOlderMessages();
      }
      if (_isNearBottom()) {
        _unlockAutoScroll();
      } else if (_distanceToBottom() > _scrollLockDistance) {
        _lockAutoScroll();
      }
    }
    if (notification is ScrollUpdateNotification ||
        notification is UserScrollNotification ||
        notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _updateScrollToBottomVisibility();
    }
    return false;
  }

  bool _isNearTop() {
    if (!_scrollController.hasClients) {
      return false;
    }
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        _loadOlderDistance;
  }

  bool _shouldAutoScrollForUpdate() {
    if (_userIsDragging || _userScrollLocked) {
      return false;
    }
    if (_autoScrollEnabled || _isNearBottom()) {
      _autoScrollEnabled = true;
      return true;
    }
    return false;
  }

  void _lockAutoScroll() {
    _userScrollLocked = true;
    _autoScrollEnabled = false;
  }

  void _unlockAutoScroll() {
    _userScrollLocked = false;
    _autoScrollEnabled = true;
  }

  void _updateScrollToBottomVisibility() {
    if (!_scrollController.hasClients) {
      return;
    }
    final shouldShow = _distanceToBottom() > _showScrollToBottomDistance;
    if (shouldShow == _showScrollToBottom) {
      return;
    }
    setState(() {
      _showScrollToBottom = shouldShow;
    });
  }

  void _jumpToBottom() {
    _unlockAutoScroll();
    _scrollToBottom();
  }

  void _loadOlderMessages() {
    if (_isLoadingOlderMessages) {
      return;
    }
    final totalDisplayMessages = _coalesceAssistantMessages(
      widget.messages,
    ).length;
    if (_visibleMessageCount >= totalDisplayMessages) {
      return;
    }
    _isLoadingOlderMessages = true;
    final oldMaxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() {
      final nextVisibleCount = _visibleMessageCount + _messagePageSize;
      _visibleMessageCount = nextVisibleCount > totalDisplayMessages
          ? totalDisplayMessages
          : nextVisibleCount;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isLoadingOlderMessages = false;
        return;
      }
      final delta =
          _scrollController.position.maxScrollExtent - oldMaxScrollExtent;
      _scrollController.jumpTo(oldPixels + delta);
      _isLoadingOlderMessages = false;
      _updateScrollToBottomVisibility();
    });
  }

  bool _startsNewUserTurn(ChatPanel oldWidget) {
    if (widget.messages.isEmpty || oldWidget.messages.isEmpty) {
      return false;
    }
    if (oldWidget.messages.last.id == widget.messages.last.id) {
      return false;
    }
    return widget.messages.last.role == MessageRole.user;
  }

  String _lastMessageData(ChatPanel panel) {
    if (panel.messages.isEmpty) {
      return '';
    }
    final blocks = panel.messages.last.blocks;
    if (blocks.isEmpty) {
      return '';
    }
    return blocks.last.data.toString();
  }

  @override
  Widget build(BuildContext context) {
    final allDisplayMessages = _coalesceAssistantMessages(widget.messages);
    final hiddenMessageCount = allDisplayMessages.length - _visibleMessageCount;
    final hasOlderMessages = hiddenMessageCount > 0;
    final displayMessages = hasOlderMessages
        ? allDisplayMessages.sublist(hiddenMessageCount)
        : allDisplayMessages;
    return Column(
      children: [
        WorkspaceHeader(workspace: widget.workspace),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount:
                      displayMessages.length + (hasOlderMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasOlderMessages && index == displayMessages.length) {
                      return _LoadEarlierMessagesButton(
                        hiddenCount: hiddenMessageCount,
                        onPressed: _loadOlderMessages,
                      );
                    }
                    final messageIndex = displayMessages.length - index - 1;
                    return MessageView(
                      message: displayMessages[messageIndex],
                      onOpenWebAppArtifact: widget.onOpenWebAppArtifact,
                      onApproveCapability: widget.onApproveCapability,
                      onDenyCapability: widget.onDenyCapability,
                    );
                  },
                ),
              ),
              if (_showScrollToBottom)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    tooltip: '滚动到底部',
                    onPressed: _jumpToBottom,
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _PromptComposer(
          controller: widget.composerController,
          isSending: widget.isSending,
          onSendPrompt: widget.onSendPrompt,
          pendingAttachments: widget.pendingAttachments,
          onAddFile: widget.onAddFile,
          onAddImage: widget.onAddImage,
          onRemovePendingAttachment: widget.onRemovePendingAttachment,
        ),
      ],
    );
  }

  List<AgentMessage> _coalesceAssistantMessages(List<AgentMessage> messages) {
    final displayMessages = <AgentMessage>[];
    for (final message in messages) {
      final previous = displayMessages.isEmpty ? null : displayMessages.last;
      if (message.role == MessageRole.assistant &&
          previous?.role == MessageRole.assistant) {
        displayMessages[displayMessages.length - 1] = AgentMessage(
          id: '${previous!.id}+${message.id}',
          role: previous.role,
          createdAt: previous.createdAt,
          blocks: [...previous.blocks, ...message.blocks],
        );
        continue;
      }
      displayMessages.add(message);
    }
    return displayMessages;
  }
}

class _LoadEarlierMessagesButton extends StatelessWidget {
  const _LoadEarlierMessagesButton({
    required this.hiddenCount,
    required this.onPressed,
  });

  final int hiddenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
          label: Text('加载更早消息 · $hiddenCount'),
        ),
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.isSending,
    required this.onSendPrompt,
    required this.pendingAttachments,
    required this.onAddFile,
    required this.onAddImage,
    required this.onRemovePendingAttachment,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSendPrompt;
  final List<MessageBlock> pendingAttachments;
  final VoidCallback onAddFile;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemovePendingAttachment;

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSending) const LinearProgressIndicator(),
                if (isSending) const SizedBox(height: 8),
                if (pendingAttachments.isNotEmpty) ...[
                  _PendingAttachmentStrip(
                    attachments: pendingAttachments,
                    onRemove: onRemovePendingAttachment,
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '添加文件',
                      icon: const Icon(Icons.attach_file),
                      onPressed: isSending ? null : onAddFile,
                    ),
                    IconButton(
                      tooltip: '添加图片',
                      icon: const Icon(Icons.image_outlined),
                      onPressed: isSending ? null : onAddImage,
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          maxHeight: 132,
                        ),
                        child: TextField(
                          controller: controller,
                          enabled: !isSending,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: '输入任务',
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF7FAF6),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: _composerBorder(context),
                            enabledBorder: _composerBorder(context),
                          ),
                          onSubmitted: (_) => onSendPrompt(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(68, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      onPressed: isSending ? null : onSendPrompt,
                      child: Text(isSending ? '发送中' : '发送'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _composerBorder(BuildContext context) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _PendingAttachmentStrip extends StatelessWidget {
  const _PendingAttachmentStrip({
    required this.attachments,
    required this.onRemove,
  });

  final List<MessageBlock> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var index = 0; index < attachments.length; index += 1)
            InputChip(
              avatar: Icon(_iconFor(attachments[index]), size: 18),
              label: Text(_labelFor(attachments[index])),
              tooltip: _tooltipFor(attachments[index]),
              onDeleted: () => onRemove(index),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(MessageBlock block) {
    return block.type == MessageBlockType.image
        ? Icons.image_outlined
        : Icons.insert_drive_file_outlined;
  }

  String _labelFor(MessageBlock block) {
    final name = block.data['name'] as String? ?? '未命名附件';
    final bytes = block.data['bytes'];
    if (bytes is! int) {
      return name;
    }
    return '$name · ${_formatBytes(bytes)}';
  }

  String _tooltipFor(MessageBlock block) {
    final uri = block.data['uri'] as String? ?? '';
    return uri.isEmpty ? _labelFor(block) : uri;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}
