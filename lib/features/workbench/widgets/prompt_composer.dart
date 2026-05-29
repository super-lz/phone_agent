import 'package:flutter/material.dart';

import '../../../application/agent/agent_run_state.dart';
import '../../../domain/conversation/message_block.dart';

class PromptComposer extends StatelessWidget {
  const PromptComposer({
    required this.controller,
    required this.isSending,
    required this.currentRun,
    required this.onSendPrompt,
    required this.onCancelRun,
    required this.pendingAttachments,
    required this.onAddFile,
    required this.onAddImage,
    required this.onRemovePendingAttachment,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final AgentRunSnapshot? currentRun;
  final VoidCallback onSendPrompt;
  final VoidCallback onCancelRun;
  final List<MessageBlock> pendingAttachments;
  final VoidCallback onAddFile;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemovePendingAttachment;

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSending && currentRun != null) ...[
                _AgentRunStatusBar(run: currentRun),
                const SizedBox(height: 8),
              ],
              if (pendingAttachments.isNotEmpty) ...[
                _PendingAttachmentStrip(
                  attachments: pendingAttachments,
                  onRemove: onRemovePendingAttachment,
                ),
                const SizedBox(height: 8),
              ],
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '添加附件',
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: isSending
                          ? null
                          : () => _showAttachmentMenu(context),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: '问我任何问题...',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                        onSubmitted: (_) {
                          if (!isSending && controller.text.trim().isNotEmpty) {
                            onSendPrompt();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        final canSend = !isSending &&
                            (value.text.trim().isNotEmpty ||
                                pendingAttachments.isNotEmpty);

                        if (isSending) {
                          return IconButton.filled(
                            onPressed: onCancelRun,
                            icon: const Icon(Icons.stop, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              minimumSize: const Size(40, 40),
                            ),
                          );
                        }

                        return IconButton.filled(
                          onPressed: canSend ? onSendPrompt : null,
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.white,
                            minimumSize: const Size(40, 40),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttachmentMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('上传图片'),
                onTap: () {
                  Navigator.pop(context);
                  onAddImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('上传文件'),
                onTap: () {
                  Navigator.pop(context);
                  onAddFile();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _AgentRunStatusBar extends StatelessWidget {
  const _AgentRunStatusBar({required this.run});

  final AgentRunSnapshot? run;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final phase = run?.phaseLabel ?? '启动中';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            phase,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
