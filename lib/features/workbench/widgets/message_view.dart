import 'package:flutter/material.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final displayBlocks = _displayBlocks(message);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                _buildAvatar(context, isUser),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? colorScheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    boxShadow: [
                      if (isUser)
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      else
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                    ],
                    border: isUser
                        ? null
                        : Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.copyWith(
                        bodyMedium: TextStyle(
                          color: isUser
                              ? Colors.white
                              : const Color(0xFF1F2937),
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
              if (isUser) ...[
                const SizedBox(width: 8),
                _buildAvatar(context, isUser),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, bool isUser) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? Colors.grey.shade200 : colorScheme.primary,
      child: Icon(
        isUser ? Icons.person : Icons.bolt,
        size: 18,
        color: isUser ? Colors.grey.shade600 : Colors.white,
      ),
    );

    if (isUser) {
      return avatar;
    }

    return Tooltip(message: 'Agent', child: avatar);
  }

  List<MessageBlock> _displayBlocks(AgentMessage message) {
    if (message.role != MessageRole.assistant) {
      return message.blocks;
    }
    if (message.blocks.any(
      (block) => block.type == MessageBlockType.taskProgress,
    )) {
      return message.blocks;
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
          'status': visibleBlocks.isEmpty ? 'processing' : 'completed',
        },
      ),
      ...visibleBlocks,
    ];
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
