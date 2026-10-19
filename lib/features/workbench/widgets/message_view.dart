import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../domain/conversation/message_block.dart';
import 'agent_process_entries.dart';
import 'message_block_view.dart';

export 'message_block_view.dart';

class MessageView extends StatelessWidget {
  const MessageView({
    required this.message,
    required this.onOpenWebAppArtifact,
    this.currentRun,
    this.onApproveCapability,
    this.onDenyCapability,
    super.key,
  });

  final AgentMessage message;
  final AgentRunSnapshot? currentRun;
  final ValueChanged<String> onOpenWebAppArtifact;
  final ValueChanged<Map<String, Object?>>? onApproveCapability;
  final ValueChanged<Map<String, Object?>>? onDenyCapability;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final colors = context.phoneAgentColors;
    final displayBlocks = _displayBlocks(message);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Tooltip(
              message: isUser ? 'You' : 'Agent',
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.symmetric(
                  horizontal: isUser ? 16 : 0,
                  vertical: isUser ? 12 : 4,
                ),
                decoration: isUser
                    ? BoxDecoration(
                        color: colors.outgoingBubbleBackground,
                        borderRadius: _bubbleRadius(),
                      )
                    : null,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.copyWith(
                      bodyMedium:
                          (Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle())
                              .copyWith(
                                color: isUser
                                    ? colors.outgoingMessageText
                                    : colors.messageText,
                                fontSize: 15,
                                height: 1.5,
                                letterSpacing: 0,
                              ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < displayBlocks.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: MessageBlockView(
                            block: displayBlocks[index],
                            currentRun:
                                index ==
                                    displayBlocks.lastIndexWhere(
                                      (block) =>
                                          block.type ==
                                          MessageBlockType.taskProgress,
                                    )
                                ? currentRun
                                : null,
                            onOpenWebAppArtifact: onOpenWebAppArtifact,
                            onApproveCapability: onApproveCapability,
                            onDenyCapability: onDenyCapability,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BorderRadius _bubbleRadius() => const BorderRadius.only(
    topLeft: Radius.circular(22),
    topRight: Radius.circular(8),
    bottomLeft: Radius.circular(22),
    bottomRight: Radius.circular(22),
  );

  List<MessageBlock> _displayBlocks(AgentMessage message) {
    if (message.role != MessageRole.assistant) {
      return message.blocks;
    }
    if (message.blocks.any(
      (block) => block.type == MessageBlockType.taskProgress,
    )) {
      return [
        ...message.blocks.where(
          (block) => block.type == MessageBlockType.taskProgress,
        ),
        ..._displayBlocks(
          AgentMessage(
            id: message.id,
            role: message.role,
            createdAt: message.createdAt,
            blocks: message.blocks
                .where((block) => block.type != MessageBlockType.taskProgress)
                .toList(growable: false),
          ),
        ),
      ];
    }

    final lastProcessIndex = message.blocks.lastIndexWhere(_isProcessBlock);
    if (lastProcessIndex < 0) {
      return message.blocks;
    }

    final processBlocks = <MessageBlock>[];
    final visibleBlocks = <MessageBlock>[];
    for (var index = 0; index < message.blocks.length; index += 1) {
      final block = message.blocks[index];
      if (_isProcessBlock(block) ||
          index <= lastProcessIndex && _isIntermediateContentBlock(block)) {
        processBlocks.add(block);
      } else {
        visibleBlocks.add(block);
      }
    }

    return [
      MessageBlock(
        type: MessageBlockType.taskProgress,
        data: {
          'blocks': processBlocks,
          'status': _processStatus(processBlocks, visibleBlocks),
        },
      ),
      ...visibleBlocks,
    ];
  }

  String _processStatus(
    List<MessageBlock> processBlocks,
    List<MessageBlock> visibleBlocks,
  ) {
    if (currentRun?.isActive == true) return 'processing';
    if (visibleBlocks.isNotEmpty) return 'completed';
    final steps = agentProcessEntries(processBlocks).whereType<ToolStepEntry>();
    if (steps.isEmpty) return 'processing';
    return steps.every((step) => step.result != null)
        ? 'completed'
        : 'processing';
  }

  bool _isProcessBlock(MessageBlock block) {
    if (block.type == MessageBlockType.markdownText &&
        block.data['intermediate'] == true) {
      return true;
    }
    switch (block.type) {
      case MessageBlockType.toolCall:
      case MessageBlockType.toolResult:
      case MessageBlockType.taskProgress:
      case MessageBlockType.citation:
        return true;
      case MessageBlockType.markdownText:
      case MessageBlockType.codeBlock:
      case MessageBlockType.image:
      case MessageBlockType.fileAttachment:
      case MessageBlockType.approvalRequest:
      case MessageBlockType.todoList:
      case MessageBlockType.artifactCard:
      case MessageBlockType.webAppCard:
      case MessageBlockType.errorCard:
        return false;
    }
  }

  bool _isIntermediateContentBlock(MessageBlock block) {
    switch (block.type) {
      case MessageBlockType.markdownText:
      case MessageBlockType.codeBlock:
      case MessageBlockType.todoList:
        return true;
      case MessageBlockType.image:
      case MessageBlockType.fileAttachment:
      case MessageBlockType.toolCall:
      case MessageBlockType.toolResult:
      case MessageBlockType.approvalRequest:
      case MessageBlockType.taskProgress:
      case MessageBlockType.citation:
      case MessageBlockType.artifactCard:
      case MessageBlockType.webAppCard:
      case MessageBlockType.errorCard:
        return false;
    }
  }
}
