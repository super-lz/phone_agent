import 'package:flutter/material.dart';

import '../../../domain/conversation/message_block.dart';
import 'agent_process_block.dart';
import 'approval_block.dart';
import 'markdown_block_view.dart';
import 'message_block_cards.dart';
import 'todo_block.dart';
import 'tool_result_view.dart';

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
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                      if (!isUser)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.copyWith(
                            bodyMedium: TextStyle(
                              color: isUser ? Colors.white : Colors.black87,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final block in displayBlocks)
                          MessageBlockView(
                            block: block,
                            onOpenWebAppArtifact: onOpenWebAppArtifact,
                            onApproveCapability: onApproveCapability,
                            onDenyCapability: onDenyCapability,
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
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? Colors.grey.shade200 : colorScheme.primary,
      child: Icon(
        isUser ? Icons.person : Icons.bolt,
        size: 18,
        color: isUser ? Colors.grey.shade600 : Colors.white,
      ),
    );
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

class MessageBlockView extends StatelessWidget {
  const MessageBlockView({
    required this.block,
    required this.onOpenWebAppArtifact,
    this.onApproveCapability,
    this.onDenyCapability,
    super.key,
  });

  final MessageBlock block;
  final ValueChanged<String> onOpenWebAppArtifact;
  final ValueChanged<Map<String, Object?>>? onApproveCapability;
  final ValueChanged<Map<String, Object?>>? onDenyCapability;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case MessageBlockType.markdownText:
        return MarkdownBlockView(text: block.data['text']! as String);
      case MessageBlockType.codeBlock:
        return CodeBlockCard(
          language: block.data['language']! as String,
          code: block.data['code']! as String,
        );
      case MessageBlockType.toolCall:
        return StructuredBlock(
          icon: Icons.play_arrow,
          title: 'Tool Call · ${block.data['capabilityId']}',
          body: block.data['input'].toString(),
          initiallyExpanded: false,
        );
      case MessageBlockType.toolResult:
        return ToolResultView(
          capabilityId: block.data['capabilityId']! as String,
          output: block.data['output']! as Map<String, Object?>,
        );
      case MessageBlockType.todoList:
        return TodoBlock(items: MessageBlock.stringList(block.data['items']));
      case MessageBlockType.image:
        return AttachmentBlock(
          icon: Icons.image_outlined,
          title: block.data['name'] as String? ?? '图片附件',
          detail: _attachmentDetail(block.data),
        );
      case MessageBlockType.fileAttachment:
        return AttachmentBlock(
          icon: Icons.insert_drive_file_outlined,
          title: block.data['name'] as String? ?? '文件附件',
          detail: _attachmentDetail(block.data),
        );
      case MessageBlockType.artifactCard:
        return StructuredBlock(
          icon: Icons.inventory_2_outlined,
          title: block.data['title']! as String,
          body: 'Artifact ID: ${block.data['artifactId']}',
        );
      case MessageBlockType.webAppCard:
        final artifactId = block.data['artifactId']! as String;
        return WebAppArtifactCard(
          title: block.data['title']! as String,
          artifactId: artifactId,
          onTap: () => onOpenWebAppArtifact(artifactId),
        );
      case MessageBlockType.errorCard:
        return StructuredBlock(
          icon: Icons.error_outline,
          title: block.data['title']! as String,
          body: block.data['detail']! as String,
        );
      case MessageBlockType.approvalRequest:
        return ApprovalBlock(
          data: block.data,
          onApprove: onApproveCapability,
          onDeny: onDenyCapability,
        );
      case MessageBlockType.taskProgress:
        return AgentProcessBlock(
          blocks: _processBlocks(block.data['blocks']),
          status: block.data['status'] as String? ?? 'completed',
          blockBuilder: (block) => MessageBlockView(
            block: block,
            onOpenWebAppArtifact: onOpenWebAppArtifact,
            onApproveCapability: onApproveCapability,
            onDenyCapability: onDenyCapability,
          ),
        );
      case MessageBlockType.citation:
        return StructuredBlock(
          icon: Icons.extension,
          title: block.type.name,
          body: block.data.toString(),
        );
    }
  }

  List<MessageBlock> _processBlocks(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value.whereType<MessageBlock>().toList(growable: false);
  }

  String _attachmentDetail(Map<String, Object?> data) {
    final parts = <String>[];
    final bytes = data['bytes'];
    final mimeType = data['mimeType'];
    final extension = data['extension'];
    final uri = data['uri'];
    if (bytes is int) {
      parts.add(_formatBytes(bytes));
    }
    if (mimeType is String && mimeType.isNotEmpty) {
      parts.add(mimeType);
    }
    if (extension is String && extension.isNotEmpty) {
      parts.add('.$extension');
    }
    if (uri is String && uri.isNotEmpty) {
      parts.add(uri);
    }
    return parts.isEmpty ? '本地附件' : parts.join(' · ');
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
