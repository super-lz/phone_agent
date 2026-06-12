import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../application/agent/context_budget.dart';
import '../../../domain/conversation/message_block.dart';
import 'composer_flow_backdrop.dart';
import 'composer_status_strip.dart';
import 'pending_attachment_strip.dart';

class PromptComposer extends StatelessWidget {
  const PromptComposer({
    required this.controller,
    required this.isSending,
    required this.currentRun,
    required this.contextBudget,
    required this.onSendPrompt,
    required this.onCancelRun,
    required this.pendingAttachments,
    required this.onAddFile,
    required this.onAddImage,
    required this.onTakePhoto,
    required this.onRemovePendingAttachment,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final AgentRunSnapshot? currentRun;
  final ContextBudgetSnapshot? contextBudget;
  final VoidCallback onSendPrompt;
  final VoidCallback onCancelRun;
  final List<MessageBlock> pendingAttachments;
  final VoidCallback onAddFile;
  final VoidCallback onAddImage;
  final VoidCallback onTakePhoto;
  final ValueChanged<int> onRemovePendingAttachment;

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final colors = context.phoneAgentColors;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.composerSurface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: ComposerFlowBackdrop(isSending: isSending),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ComposerStatusStrip(
                        controller: controller,
                        isSending: isSending,
                        currentRun: currentRun,
                        contextBudget: contextBudget,
                      ),
                      const SizedBox(height: 8),
                      if (pendingAttachments.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: PendingAttachmentStrip(
                            attachments: pendingAttachments,
                            onRemove: onRemovePendingAttachment,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: '添加附件',
                                icon: Icon(
                                  Icons.add_rounded,
                                  color: colors.primaryAction,
                                  size: 24,
                                ),
                                style: IconButton.styleFrom(
                                  fixedSize: const Size(40, 40),
                                  minimumSize: const Size(40, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: isSending
                                    ? null
                                    : () {
                                        _showAttachmentMenu(context);
                                      },
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colors.inputBackground.withValues(
                                      alpha: isSending ? 0.82 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: colors.border.withValues(
                                        alpha: isSending ? 0.72 : 1,
                                      ),
                                    ),
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.send,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.4,
                                      letterSpacing: 0,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '问我任何问题...',
                                      hintStyle: TextStyle(
                                        color: colors.inputHint,
                                      ),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                    ),
                                    onSubmitted: (_) {
                                      if (!isSending &&
                                          controller.text.trim().isNotEmpty) {
                                        onSendPrompt();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, child) {
                                  final canSend =
                                      !isSending &&
                                      (value.text.trim().isNotEmpty ||
                                          pendingAttachments.isNotEmpty);

                                  if (isSending) {
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: IconButton.filled(
                                        onPressed: onCancelRun,
                                        tooltip: '停止',
                                        icon: const Icon(
                                          Icons.stop_rounded,
                                          size: 20,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: colors.primaryAction,
                                          foregroundColor: Colors.white,
                                          fixedSize: const Size(48, 48),
                                          minimumSize: const Size(48, 48),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    );
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: IconButton.filled(
                                      onPressed: canSend ? onSendPrompt : null,
                                      tooltip: '发送',
                                      icon: const Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 20,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: colors.primaryAction,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            colors.primaryActionDisabled,
                                        disabledForegroundColor: Colors.white
                                            .withValues(alpha: 0.72),
                                        fixedSize: const Size(48, 48),
                                        minimumSize: const Size(48, 48),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAttachmentMenu(BuildContext context) async {
    final colors = context.phoneAgentColors;
    final action = await showModalBottomSheet<_AttachmentAction>(
      context: context,
      backgroundColor: colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('拍照上传'),
                onTap: () {
                  Navigator.pop(context, _AttachmentAction.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('从相册选择'),
                onTap: () {
                  Navigator.pop(context, _AttachmentAction.image);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('上传文件'),
                onTap: () {
                  Navigator.pop(context, _AttachmentAction.file);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _AttachmentAction.camera:
        onTakePhoto();
      case _AttachmentAction.image:
        onAddImage();
      case _AttachmentAction.file:
        onAddFile();
    }
  }
}

enum _AttachmentAction { camera, image, file }
