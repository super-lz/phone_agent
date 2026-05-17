import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/conversation/message_block.dart';
import '../../../domain/workspace/workspace.dart';
import 'message_view.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.workspace,
    required this.messages,
    required this.composerController,
    required this.isSending,
    required this.onSendPrompt,
    required this.onOpenWebAppArtifact,
    super.key,
  });

  final AgentWorkspace workspace;
  final List<AgentMessage> messages;
  final TextEditingController composerController;
  final bool isSending;
  final VoidCallback onSendPrompt;
  final ValueChanged<String> onOpenWebAppArtifact;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scrollController = ScrollController();
  bool _autoScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.isSending != widget.isSending ||
        _lastMessageData(oldWidget) != _lastMessageData(widget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_autoScrollEnabled || _isNearBottom()) {
          _autoScrollEnabled = true;
          _scrollToBottom();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final distanceToBottom =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    return distanceToBottom < 80;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.forward:
          _autoScrollEnabled = false;
        case ScrollDirection.reverse:
        case ScrollDirection.idle:
          if (_isNearBottom()) {
            _autoScrollEnabled = true;
          }
      }
    }
    if (notification is ScrollEndNotification && _isNearBottom()) {
      _autoScrollEnabled = true;
    }
    return false;
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
    return Column(
      children: [
        _WorkspaceHeader(workspace: widget.workspace),
        const Divider(height: 1),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                return MessageView(
                  message: widget.messages[index],
                  onOpenWebAppArtifact: widget.onOpenWebAppArtifact,
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        _PromptComposer(
          controller: widget.composerController,
          isSending: widget.isSending,
          onSendPrompt: widget.onSendPrompt,
        ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.workspace});

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

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.isSending,
    required this.onSendPrompt,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSendPrompt;

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '添加文件',
                      icon: const Icon(Icons.attach_file),
                      onPressed: isSending ? null : () {},
                    ),
                    IconButton(
                      tooltip: '添加图片',
                      icon: const Icon(Icons.image_outlined),
                      onPressed: isSending ? null : () {},
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
