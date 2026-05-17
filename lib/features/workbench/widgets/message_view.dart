import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../domain/conversation/message_block.dart';
import 'tool_result_view.dart';

class MessageView extends StatelessWidget {
  const MessageView({
    required this.message,
    required this.onOpenWebAppArtifact,
    super.key,
  });

  final AgentMessage message;
  final ValueChanged<String> onOpenWebAppArtifact;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFFE3F2EA) : Colors.white,
              border: Border.all(color: const Color(0xFFE0E5DD)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _roleLabel(message.role),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final block in message.blocks)
                    MessageBlockView(
                      block: block,
                      onOpenWebAppArtifact: onOpenWebAppArtifact,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _roleLabel(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return 'User';
      case MessageRole.assistant:
        return 'Agent';
      case MessageRole.system:
        return 'System';
    }
  }
}

class MessageBlockView extends StatelessWidget {
  const MessageBlockView({
    required this.block,
    required this.onOpenWebAppArtifact,
    super.key,
  });

  final MessageBlock block;
  final ValueChanged<String> onOpenWebAppArtifact;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case MessageBlockType.markdownText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MarkdownBody(data: block.data['text']! as String),
        );
      case MessageBlockType.codeBlock:
        return _CodeBlock(
          language: block.data['language']! as String,
          code: block.data['code']! as String,
        );
      case MessageBlockType.toolCall:
        return _StructuredBlock(
          icon: Icons.play_arrow,
          title: 'Tool Call · ${block.data['capabilityId']}',
          body: block.data['input'].toString(),
        );
      case MessageBlockType.toolResult:
        return ToolResultView(
          capabilityId: block.data['capabilityId']! as String,
          output: block.data['output']! as Map<String, Object?>,
        );
      case MessageBlockType.todoList:
        return _TodoBlock(items: block.data['items']! as List<String>);
      case MessageBlockType.artifactCard:
        return _StructuredBlock(
          icon: Icons.inventory_2_outlined,
          title: block.data['title']! as String,
          body: 'Artifact ID: ${block.data['artifactId']}',
        );
      case MessageBlockType.webAppCard:
        final artifactId = block.data['artifactId']! as String;
        return _StructuredBlock(
          icon: Icons.web_asset,
          title: block.data['title']! as String,
          body: '点击预览 · Artifact ID: $artifactId',
          onTap: () => onOpenWebAppArtifact(artifactId),
        );
      case MessageBlockType.errorCard:
        return _StructuredBlock(
          icon: Icons.error_outline,
          title: block.data['title']! as String,
          body: block.data['detail']! as String,
        );
      case MessageBlockType.image:
      case MessageBlockType.fileAttachment:
      case MessageBlockType.approvalRequest:
      case MessageBlockType.taskProgress:
      case MessageBlockType.citation:
        return _StructuredBlock(
          icon: Icons.extension,
          title: block.type.name,
          body: block.data.toString(),
        );
    }
  }
}

class _TodoBlock extends StatelessWidget {
  const _TodoBlock({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Row(
              children: [
                const Icon(Icons.check, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17211B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(language, style: const TextStyle(color: Color(0xFF9CCFB5))),
          const SizedBox(height: 8),
          SelectableText(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StructuredBlock extends StatelessWidget {
  const _StructuredBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7DED2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(body),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
