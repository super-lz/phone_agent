import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/capabilities/capability_runtime.dart';
import '../../../domain/conversation/message_block.dart';
import 'message_block_view.dart';

export 'message_block_view.dart';

class MessageView extends StatelessWidget {
  const MessageView({
    required this.message,
    required this.onOpenWebAppArtifact,
    this.onApproveCapability,
    this.onDenyCapability,
    super.key,
  });

  final AgentMessage message;
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
        final maxWidth = constraints.maxWidth < 480
            ? constraints.maxWidth * 0.82
            : constraints.maxWidth * 0.72;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth.clamp(260.0, 620.0).toDouble(),
            ),
            child: Tooltip(
              message: isUser ? 'You' : 'Agent',
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? colors.outgoingBubbleBackground
                      : colors.incomingBubbleBackground,
                  borderRadius: _bubbleRadius(isUser),
                  border: isUser
                      ? null
                      : Border.all(color: colors.incomingBubbleBorder),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.copyWith(
                      bodyMedium: TextStyle(
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
                      for (final block in displayBlocks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: MessageBlockView(
                            block: block,
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

  BorderRadius _bubbleRadius(bool isUser) {
    const round = Radius.circular(22);
    const square = Radius.circular(8);
    if (isUser) {
      return const BorderRadius.only(
        topLeft: round,
        topRight: square,
        bottomLeft: round,
        bottomRight: round,
      );
    }
    return const BorderRadius.only(
      topLeft: square,
      topRight: round,
      bottomLeft: round,
      bottomRight: round,
    );
  }

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
        ...message.blocks.where(
          (block) => block.type != MessageBlockType.taskProgress,
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
    if (visibleBlocks.isNotEmpty) {
      return 'completed';
    }
    final toolCalls = processBlocks
        .where((block) => block.type == MessageBlockType.toolCall)
        .map((block) => block.data['capabilityId'] as String?)
        .whereType<String>()
        .toList(growable: false);
    if (toolCalls.isEmpty) {
      return 'processing';
    }
    final resultIds = processBlocks
        .where((block) => block.type == MessageBlockType.toolResult)
        .map((block) => block.data['capabilityId'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final allCallsHaveResults = toolCalls.every((name) {
      final expectedCapabilityId = CapabilityRuntime.capabilityIdForToolName(
        name,
      );
      return resultIds.contains(name) ||
          expectedCapabilityId != null &&
              resultIds.contains(expectedCapabilityId);
    });
    return allCallsHaveResults ? 'completed' : 'processing';
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
