import '../../core/logging/app_logger.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/conversation/message_block.dart';
import '../../domain/models/model_provider_config.dart';

class ConversationContextBuilder {
  const ConversationContextBuilder({
    this.maxRecentChars = 12000,
    this.maxSummaryChars = 4000,
  });

  final int maxRecentChars;
  final int maxSummaryChars;

  Future<ConversationContext> build({
    required List<AgentMessage> messages,
    OpenAiCompatibleChatClient? chatClient,
    ModelProviderConfig? provider,
    String? apiKey,
  }) async {
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

    String summary = '';
    if (orderedOlder.isNotEmpty) {
      if (chatClient != null && provider != null && apiKey != null) {
        summary = await _semanticSummarize(
          entries: orderedOlder,
          chatClient: chatClient,
          provider: provider,
          apiKey: apiKey,
        );
      } else {
        summary = _compactOlderEntries(orderedOlder);
      }
    }

    AppLogger.info('conversation_context.build', {
      'inputMessages': messages.length,
      'recentMessages': orderedRecent.length,
      'summaryChars': summary.length,
      'recentChars': usedChars,
      'isSemantic': chatClient != null,
    });
    return ConversationContext(summary: summary, recentEntries: orderedRecent);
  }

  Future<String> _semanticSummarize({
    required List<ConversationContextEntry> entries,
    required OpenAiCompatibleChatClient chatClient,
    required ModelProviderConfig provider,
    required String apiKey,
  }) async {
    try {
      final chunks = _summaryChunks(entries);
      if (chunks.length == 1) {
        return _summarizeTranscript(
          transcript: chunks.single,
          chatClient: chatClient,
          provider: provider,
          apiKey: apiKey,
          maxChars: maxSummaryChars,
        );
      }
      final partials = <String>[];
      final partialLimit = (maxSummaryChars ~/ 2).clamp(600, maxSummaryChars);
      for (final chunk in chunks) {
        partials.add(
          await _summarizeTranscript(
            transcript: chunk,
            chatClient: chatClient,
            provider: provider,
            apiKey: apiKey,
            maxChars: partialLimit,
          ),
        );
      }
      return _summarizeTranscript(
        transcript: partials.join('\n'),
        chatClient: chatClient,
        provider: provider,
        apiKey: apiKey,
        maxChars: maxSummaryChars,
      );
    } on Object catch (error) {
      AppLogger.warning('conversation_context.summarize_failed', {
        'error': error.toString(),
      });
      return _compactOlderEntries(entries);
    }
  }

  Future<String> _summarizeTranscript({
    required String transcript,
    required OpenAiCompatibleChatClient chatClient,
    required ModelProviderConfig provider,
    required String apiKey,
    required int maxChars,
  }) async {
    final prompt =
        '请为以下对话历史生成一段高度压缩的语义摘要。\n'
        '要求：\n'
        '1. 保留用户的核心目标和长期任务。\n'
        '2. 保留关键事实、已完成的重要动作、工具结果和 Artifact。\n'
        '3. 保留未解决的问题、失败原因和用户明确约束。\n'
        '4. 摘要必须极其精炼，字数控制在 ${maxChars ~/ 2} 字以内。\n'
        '5. 不要包含客套话或元描述。\n\n'
        '对话历史：\n$transcript';
    final response = await chatClient.generateResponse(
      provider: provider,
      apiKey: apiKey,
      prompt: prompt,
      systemPrompt: '你是一个高效的对话上下文压缩助手，擅长提取关键语义。',
    );
    return _truncate(response.trim(), maxChars);
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
      case MessageBlockType.toolResult:
        return _toolResultSummary(block);
      case MessageBlockType.toolCall:
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

  String _toolResultSummary(MessageBlock block) {
    final capabilityId = block.data['capabilityId'] as String? ?? 'unknown';
    final output = block.data['output'];
    if (output is! Map<Object?, Object?>) {
      return '工具结果 $capabilityId: 无结构化输出';
    }

    final parts = <String>['工具结果 $capabilityId'];
    final ok = output['ok'];
    if (ok is bool) {
      parts.add(ok ? '成功' : '失败');
    }
    for (final key in const [
      'summary',
      'userMessage',
      'detail',
      'error',
      'title',
      'type',
      'artifactId',
      'workspaceId',
      'activeWorkspaceId',
      'path',
      'workspacePath',
      'entryPath',
      'manifestPath',
      'projectId',
      'versionPath',
      'runtimeLogPath',
      'notificationId',
      'eventId',
    ]) {
      final value = _safeScalar(output[key]);
      if (value != null) {
        parts.add('$key=$value');
      }
    }

    final version = output['version'];
    if (version is num) {
      parts.add('version=$version');
    }
    final paths = _pathListFrom(output['files']);
    if (paths.isNotEmpty) {
      parts.add('files=${paths.join(', ')}');
    }
    final changedPaths = _stringItems(output['changedFiles']);
    if (changedPaths.isNotEmpty) {
      parts.add('changedFiles=${changedPaths.take(8).join(', ')}');
    }
    return _truncate(parts.join(' · '), 900);
  }

  String? _safeScalar(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return _truncate(value.replaceAll(RegExp(r'\s+'), ' ').trim(), 240);
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  List<String> _pathListFrom(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    final paths = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        paths.add(item.trim());
      } else if (item is Map<Object?, Object?>) {
        final path = item['path'];
        if (path is String && path.trim().isNotEmpty) {
          paths.add(path.trim());
        }
      }
      if (paths.length >= 8) {
        break;
      }
    }
    return paths;
  }

  List<String> _stringItems(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .map((item) => _truncate(item.trim(), 160))
        .toList(growable: false);
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

  List<String> _summaryChunks(List<ConversationContextEntry> entries) {
    final maxChunkChars = (maxSummaryChars * 4).clamp(4000, 24000);
    final chunks = <String>[];
    final buffer = StringBuffer();
    for (final entry in entries) {
      final oneLine = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (oneLine.isEmpty) {
        continue;
      }
      final line = '- ${entry.role.label}: ${_truncate(oneLine, 1200)}';
      if (buffer.isNotEmpty &&
          buffer.length + line.length + 1 > maxChunkChars) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
      if (chunks.length >= 6) {
        if (buffer.isNotEmpty) {
          buffer.writeln('- System: 后续更早历史过长，已停止继续加入本轮压缩输入。');
        }
        break;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(line);
    }
    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString());
    }
    if (chunks.isEmpty) {
      return const [''];
    }
    return chunks;
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
