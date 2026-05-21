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
                if (isSending) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
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
                          onSubmitted: (_) {
                            if (!isSending) {
                              onSendPrompt();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isSending)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(74, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: onCancelRun,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('停止'),
                      )
                    else
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(68, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: onSendPrompt,
                        child: const Text('发送'),
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

class _AgentRunStatusBar extends StatelessWidget {
  const _AgentRunStatusBar({required this.run});

  final AgentRunSnapshot? run;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final phase = run?.phaseLabel ?? '启动中';
    final detail = run?.detail ?? '正在启动本轮 Agent 任务。';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.radar_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$phase\n$detail',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
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
