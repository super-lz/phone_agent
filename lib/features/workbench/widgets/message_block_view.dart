import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/conversation/message_block.dart';
import 'agent_process_block.dart';
import 'approval_block.dart';
import 'markdown_block_view.dart';
import 'message_block_cards.dart';
import 'todo_block.dart';
import 'tool_call_summary.dart';
import 'tool_result_view.dart';

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
        final capabilityId = block.data['capabilityId'] as String? ?? 'tool';
        return StructuredBlock(
          icon: Icons.play_arrow,
          title: 'Tool Call · $capabilityId',
          body: toolCallSummary(capabilityId, block.data['input']),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AttachmentBlock(
              icon: Icons.image_outlined,
              title: block.data['name'] as String? ?? '图片附件',
              detail: _attachmentDetail(block.data),
            ),
            const SizedBox(height: 8),
            _ImagePreview(uri: block.data['uri'] as String?),
          ],
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
    return value
        .map(MessageBlock.tryFromJson)
        .whereType<MessageBlock>()
        .toList(growable: false);
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.uri});

  final String? uri;

  @override
  Widget build(BuildContext context) {
    if (uri == null || uri!.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget? image;
    try {
      final fileUri = Uri.parse(uri!);
      if (fileUri.isScheme('file')) {
        image = Image.file(
          File(fileUri.toFilePath()),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _ErrorPlaceholder(error: error),
        );
      } else if (fileUri.isScheme('http') || fileUri.isScheme('https')) {
        image = Image.network(
          uri!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _ErrorPlaceholder(error: error),
        );
      }
    } catch (e) {
      return _ErrorPlaceholder(error: e);
    }

    if (image == null) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (context) => Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(child: Center(child: image!)),
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: image,
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: 150,
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
          const SizedBox(height: 4),
          Text(
            '图片读取失败',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
