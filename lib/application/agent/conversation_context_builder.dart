import '../../core/logging/app_logger.dart';
import '../../domain/conversation/message_block.dart';

class ConversationContextBuilder {
  const ConversationContextBuilder({
    this.maxRecentChars = 12000,
    this.maxSummaryChars = 4000,
  });

  final int maxRecentChars;
  final int maxSummaryChars;

  ConversationContext build(List<AgentMessage> messages) {
    final entries = messages
        .map(_toTranscriptEntry)
        .whereType<ConversationContextEntry>()
        .toList(growable: false);

    var usedChars = 0;
    final recent = <ConversationContextEntry>[];
    final older = <ConversationContextEntry>[];

    for (final entry in entries.reversed) {
      final nextSize = usedChars + entry.content.length;
      if (nextSize <= maxRecentChars || recent.isEmpty) {
        recent.add(entry);
        usedChars = nextSize;
      } else {
        older.add(entry);
      }
    }

    final orderedRecent = recent.reversed.toList(growable: false);
    final orderedOlder = older.reversed.toList(growable: false);
    final summary = orderedOlder.isEmpty
        ? ''
        : _compactOlderEntries(orderedOlder);

    AppLogger.info('conversation_context.build', {
      'inputMessages': messages.length,
      'recentMessages': orderedRecent.length,
      'summaryChars': summary.length,
      'recentChars': usedChars,
    });
    return ConversationContext(summary: summary, recentEntries: orderedRecent);
  }

  ConversationContextEntry? _toTranscriptEntry(AgentMessage message) {
    final content = message.blocks
        .map(_blockToText)
        .where((part) => part.trim().isNotEmpty)
        .join('\n')
        .trim();
    if (content.isEmpty) {
      return null;
    }
    return ConversationContextEntry(role: message.role, content: content);
  }

  String _blockToText(MessageBlock block) {
    switch (block.type) {
      case MessageBlockType.markdownText:
        return block.data['text'] as String? ?? '';
      case MessageBlockType.codeBlock:
        final language = block.data['language'] as String? ?? '';
        final code = block.data['code'] as String? ?? '';
        return '代码块($language):\n$code';
      case MessageBlockType.image:
        return '图片附件: ${_attachmentSummary(block)}';
      case MessageBlockType.fileAttachment:
        return '文件附件: ${_attachmentSummary(block)}';
      case MessageBlockType.todoList:
        final items = MessageBlock.stringList(block.data['items']);
        if (items.isEmpty) {
          return '';
        }
        return 'TODO:\n${items.map((item) => '- $item').join('\n')}';
      case MessageBlockType.artifactCard:
      case MessageBlockType.webAppCard:
        return 'Artifact ${block.data['title']}: ${block.data['artifactId']}';
      case MessageBlockType.errorCard:
        return '错误 ${block.data['title']}: ${block.data['detail']}';
      case MessageBlockType.toolCall:
      case MessageBlockType.toolResult:
      case MessageBlockType.approvalRequest:
      case MessageBlockType.taskProgress:
      case MessageBlockType.citation:
        return '';
    }
  }

  String _attachmentSummary(MessageBlock block) {
    final name = block.data['name'] as String? ?? '未命名附件';
    final uri = block.data['uri'] as String? ?? '';
    final bytes = block.data['bytes'];
    final mimeType = block.data['mimeType'];
    final extension = block.data['extension'];
    final parts = <String>[name];
    if (bytes is int) {
      parts.add('$bytes bytes');
    }
    if (mimeType is String && mimeType.isNotEmpty) {
      parts.add(mimeType);
    }
    if (extension is String && extension.isNotEmpty) {
      parts.add('扩展名 .$extension');
    }
    if (uri.isNotEmpty) {
      parts.add(uri);
    }
    return parts.join(' · ');
  }

  String _compactOlderEntries(List<ConversationContextEntry> entries) {
    final lines = <String>[];
    for (final entry in entries) {
      final oneLine = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (oneLine.isEmpty) {
        continue;
      }
      lines.add('- ${entry.role.label}: ${_truncate(oneLine, 420)}');
    }
    final summary = lines.join('\n');
    return _truncate(summary, maxSummaryChars);
  }

  String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}...';
  }
}

class ConversationContext {
  const ConversationContext({
    required this.summary,
    required this.recentEntries,
  });

  final String summary;
  final List<ConversationContextEntry> recentEntries;
}

class ConversationContextEntry {
  const ConversationContextEntry({required this.role, required this.content});

  final MessageRole role;
  final String content;
}

extension on MessageRole {
  String get label {
    switch (this) {
      case MessageRole.user:
        return 'User';
      case MessageRole.assistant:
        return 'Agent';
      case MessageRole.system:
        return 'System';
    }
  }
}
