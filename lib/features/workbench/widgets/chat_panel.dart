import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../domain/conversation/message_block.dart';
import '../../../domain/workspace/workspace.dart';
import 'load_earlier_messages_button.dart';
import 'message_display_coalescer.dart';
import 'message_view.dart';
import 'prompt_composer.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.workspace,
    required this.messages,
    required this.composerController,
    required this.isSending,
    required this.currentRun,
    required this.onSendPrompt,
    required this.onCancelRun,
    required this.onOpenWebAppArtifact,
    required this.onApproveCapability,
    required this.onDenyCapability,
    required this.pendingAttachments,
    required this.onAddFile,
    required this.onAddImage,
    required this.onTakePhoto,
    required this.onRemovePendingAttachment,
    super.key,
  });

  final AgentWorkspace workspace;
  final List<AgentMessage> messages;
  final TextEditingController composerController;
  final bool isSending;
  final AgentRunSnapshot? currentRun;
  final VoidCallback onSendPrompt;
  final VoidCallback onCancelRun;
  final ValueChanged<String> onOpenWebAppArtifact;
  final ValueChanged<Map<String, Object?>> onApproveCapability;
  final ValueChanged<Map<String, Object?>> onDenyCapability;
  final List<MessageBlock> pendingAttachments;
  final VoidCallback onAddFile;
  final VoidCallback onAddImage;
  final VoidCallback onTakePhoto;
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
    final totalDisplayMessages = coalesceAssistantMessages(
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
    final totalDisplayMessages = coalesceAssistantMessages(
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
    final allDisplayMessages = coalesceAssistantMessages(widget.messages);
    final hiddenMessageCount = allDisplayMessages.length - _visibleMessageCount;
    final hasOlderMessages = hiddenMessageCount > 0;
    final displayMessages = hasOlderMessages
        ? allDisplayMessages.sublist(hiddenMessageCount)
        : allDisplayMessages;
    final colors = context.phoneAgentColors;

    return ColoredBox(
      color: colors.pageBackground,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: EdgeInsets.fromLTRB(
                      14,
                      20,
                      14,
                      MediaQuery.of(context).padding.bottom + 18,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount:
                        displayMessages.length + (hasOlderMessages ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasOlderMessages && index == displayMessages.length) {
                        return LoadEarlierMessagesButton(
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
                    right: 18,
                    bottom: 18,
                    child: FloatingActionButton.small(
                      elevation: 0,
                      backgroundColor: colors.iconButtonBackground,
                      foregroundColor: colors.primaryAction,
                      tooltip: '滚动到底部',
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          PromptComposer(
            controller: widget.composerController,
            isSending: widget.isSending,
            currentRun: widget.currentRun,
            onSendPrompt: widget.onSendPrompt,
            onCancelRun: widget.onCancelRun,
            pendingAttachments: widget.pendingAttachments,
            onAddFile: widget.onAddFile,
            onAddImage: widget.onAddImage,
            onTakePhoto: widget.onTakePhoto,
            onRemovePendingAttachment: widget.onRemovePendingAttachment,
          ),
        ],
      ),
    );
  }
}
