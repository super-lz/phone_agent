import 'dart:math' as math;

import '../../domain/conversation/message_block.dart';
import '../../domain/models/model_provider_config.dart';
import 'final_response_guard.dart';

const int conservativeContextWindowTokens = 32768;

class ContextBudgetPlanner {
  const ContextBudgetPlanner({
    this.estimator = const ContextTokenEstimator(),
    this.conservativeMaxContextTokens = conservativeContextWindowTokens,
  });

  final ContextTokenEstimator estimator;
  final int conservativeMaxContextTokens;

  ContextBudgetPlan plan({
    required ModelProviderConfig provider,
    required String systemPrompt,
    required String toolIndex,
    List<Map<String, Object?>> toolSchema = const [],
    required Object prompt,
    required List<AgentMessage> priorMessages,
  }) {
    final maxContextTokens =
        provider.effectiveMaxContextTokens ?? conservativeMaxContextTokens;
    final reservedOutputTokens = _reservedOutputTokens(
      provider,
      maxContextTokens,
    );
    final fixedTokens =
        estimator.estimateText(systemPrompt) +
        estimator.estimateObject(toolSchema) +
        estimator.estimateObject(prompt);
    final maxSummaryTokens = _maxSummaryTokens(maxContextTokens);
    final availableForRecent =
        maxContextTokens -
        reservedOutputTokens -
        fixedTokens -
        maxSummaryTokens;
    final recentTokenBudget = math.max(512, availableForRecent);
    final maxRecentChars = estimator.approxCharsForTokens(recentTokenBudget);
    final maxSummaryChars = estimator.approxCharsForTokens(maxSummaryTokens);
    final preCompressionSnapshot = snapshotForParts(
      provider: provider,
      prompt: prompt,
      systemPrompt: systemPrompt,
      toolIndex: toolIndex,
      toolSchema: toolSchema,
      summary: '',
      recentHistory: priorMessages
          .map((message) => _messageText(message))
          .where((text) => text.isNotEmpty)
          .join('\n'),
    );

    return ContextBudgetPlan(
      maxContextTokens: maxContextTokens,
      isConservativeFallback: provider.effectiveMaxContextTokens == null,
      reservedOutputTokens: reservedOutputTokens,
      maxRecentChars: maxRecentChars,
      maxSummaryChars: maxSummaryChars,
      preCompressionSnapshot: preCompressionSnapshot,
    );
  }

  ContextBudgetSnapshot snapshotForModelMessages({
    required ModelProviderConfig provider,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
  }) {
    final maxContextTokens =
        provider.effectiveMaxContextTokens ?? conservativeMaxContextTokens;
    final reservedOutputTokens = _reservedOutputTokens(
      provider,
      maxContextTokens,
    );
    final toolTokens = estimator.estimateObject(tools);
    final inputTokens = estimator.estimateObject(messages) + toolTokens;
    return ContextBudgetSnapshot(
      providerId: provider.id,
      modelName: provider.model,
      maxContextTokens: maxContextTokens,
      isConservativeFallback: provider.effectiveMaxContextTokens == null,
      reservedOutputTokens: reservedOutputTokens,
      systemTokens: 0,
      toolTokens: toolTokens,
      summaryTokens: 0,
      recentHistoryTokens: 0,
      promptTokens: inputTokens,
      inputTokens: inputTokens,
    );
  }

  ContextBudgetSnapshot snapshotForParts({
    required ModelProviderConfig provider,
    required Object prompt,
    required String systemPrompt,
    required String toolIndex,
    List<Map<String, Object?>> toolSchema = const [],
    required String summary,
    required String recentHistory,
  }) {
    final maxContextTokens =
        provider.effectiveMaxContextTokens ?? conservativeMaxContextTokens;
    final reservedOutputTokens = _reservedOutputTokens(
      provider,
      maxContextTokens,
    );
    final toolIndexTokens = estimator.estimateText(toolIndex);
    final toolTokens = toolIndexTokens + estimator.estimateObject(toolSchema);
    final systemTokens = math.max(
      0,
      estimator.estimateText(systemPrompt) - toolIndexTokens,
    );
    final summaryTokens = estimator.estimateText(summary);
    final recentHistoryTokens = estimator.estimateText(recentHistory);
    final promptTokens = estimator.estimateObject(prompt);
    final inputTokens =
        systemTokens +
        toolTokens +
        summaryTokens +
        recentHistoryTokens +
        promptTokens;
    return ContextBudgetSnapshot(
      providerId: provider.id,
      modelName: provider.model,
      maxContextTokens: maxContextTokens,
      isConservativeFallback: provider.effectiveMaxContextTokens == null,
      reservedOutputTokens: reservedOutputTokens,
      systemTokens: systemTokens,
      toolTokens: toolTokens,
      summaryTokens: summaryTokens,
      recentHistoryTokens: recentHistoryTokens,
      promptTokens: promptTokens,
      inputTokens: inputTokens,
    );
  }

  int _reservedOutputTokens(
    ModelProviderConfig provider,
    int maxContextTokens,
  ) {
    final configured = provider.defaultMaxTokens;
    if (configured != null && configured > 0) {
      return configured.clamp(1024, maxContextTokens ~/ 2).toInt();
    }
    final ratioReserve = (maxContextTokens * 0.12).round();
    return ratioReserve.clamp(2048, 8192).toInt();
  }

  int _maxSummaryTokens(int maxContextTokens) {
    return (maxContextTokens * 0.08).round().clamp(1024, 4096).toInt();
  }

  String _messageText(AgentMessage message) {
    return message.blocks
        .map((block) => _blockText(message.role, block))
        .where((text) => text.trim().isNotEmpty)
        .join('\n')
        .trim();
  }

  String _blockText(MessageRole role, MessageBlock block) {
    return switch (block.type) {
      MessageBlockType.markdownText =>
        block.data['intermediate'] == true
            ? ''
            : _assistantMarkdownHistoryText(
                role,
                block.data['text'] as String? ?? '',
              ),
      MessageBlockType.codeBlock => block.data['code'] as String? ?? '',
      MessageBlockType.image ||
      MessageBlockType.fileAttachment => block.data.toString(),
      MessageBlockType.todoList => MessageBlock.stringList(
        block.data['items'],
      ).join('\n'),
      MessageBlockType.artifactCard ||
      MessageBlockType.webAppCard ||
      MessageBlockType.errorCard => block.data.toString(),
      MessageBlockType.toolResult => _toolResultText(block),
      MessageBlockType.taskProgress => _taskProgressText(block),
      MessageBlockType.toolCall ||
      MessageBlockType.approvalRequest ||
      MessageBlockType.citation => '',
    };
  }

  String _assistantMarkdownHistoryText(MessageRole role, String text) {
    if (role == MessageRole.assistant && looksLikeRawToolProcess(text)) {
      return '';
    }
    return text;
  }

  String _toolResultText(MessageBlock block) {
    final capabilityId = block.data['capabilityId'] as String? ?? 'unknown';
    final output = block.data['output'];
    if (output is! Map<Object?, Object?>) {
      return '工具结果 $capabilityId';
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
    return parts.join(' · ');
  }

  String _taskProgressText(MessageBlock block) {
    final nestedBlocks = block.data['blocks'];
    if (nestedBlocks is! Iterable<Object?>) {
      return '';
    }
    return nestedBlocks
        .map(MessageBlock.tryFromJson)
        .whereType<MessageBlock>()
        .map((nested) {
          return switch (nested.type) {
            MessageBlockType.toolResult => _toolResultText(nested),
            MessageBlockType.artifactCard ||
            MessageBlockType.webAppCard => nested.data.toString(),
            MessageBlockType.errorCard => nested.data.toString(),
            _ => '',
          };
        })
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
  }

  String? _safeScalar(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      return singleLine.length <= 240
          ? singleLine
          : '${singleLine.substring(0, 240)}...';
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }
}

class ContextTokenEstimator {
  const ContextTokenEstimator();

  int estimateObject(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is String) {
      return estimateText(value);
    }
    if (value is Iterable<Object?>) {
      return value.fold<int>(0, (sum, item) => sum + estimateObject(item));
    }
    if (value is Map<Object?, Object?>) {
      return value.entries.fold<int>(0, (sum, entry) {
        return sum +
            estimateText(entry.key.toString()) +
            estimateObject(entry.value);
      });
    }
    return estimateText(value.toString());
  }

  int estimateText(String value) {
    if (value.isEmpty) {
      return 0;
    }
    var cjk = 0;
    var ascii = 0;
    var other = 0;
    for (final codePoint in value.runes) {
      if (_isWhitespace(codePoint)) {
        continue;
      }
      if (_isCjk(codePoint)) {
        cjk += 1;
      } else if (codePoint <= 0x7f) {
        ascii += 1;
      } else {
        other += 1;
      }
    }
    return math.max(1, cjk + other + (ascii / 4).ceil());
  }

  int approxCharsForTokens(int tokens) {
    return math.max(1200, tokens * 2);
  }

  bool _isWhitespace(int codePoint) {
    return codePoint == 0x20 ||
        codePoint == 0x09 ||
        codePoint == 0x0a ||
        codePoint == 0x0d;
  }

  bool _isCjk(int codePoint) {
    return codePoint >= 0x4e00 && codePoint <= 0x9fff ||
        codePoint >= 0x3400 && codePoint <= 0x4dbf ||
        codePoint >= 0xf900 && codePoint <= 0xfaff;
  }
}

class ContextBudgetPlan {
  const ContextBudgetPlan({
    required this.maxContextTokens,
    required this.isConservativeFallback,
    required this.reservedOutputTokens,
    required this.maxRecentChars,
    required this.maxSummaryChars,
    required this.preCompressionSnapshot,
  });

  final int maxContextTokens;
  final bool isConservativeFallback;
  final int reservedOutputTokens;
  final int maxRecentChars;
  final int maxSummaryChars;
  final ContextBudgetSnapshot preCompressionSnapshot;
}

class ContextBudgetSnapshot {
  const ContextBudgetSnapshot({
    required this.providerId,
    required this.modelName,
    required this.maxContextTokens,
    required this.isConservativeFallback,
    required this.reservedOutputTokens,
    required this.systemTokens,
    required this.toolTokens,
    required this.summaryTokens,
    required this.recentHistoryTokens,
    required this.promptTokens,
    required this.inputTokens,
  });

  final String providerId;
  final String modelName;
  final int maxContextTokens;
  final bool isConservativeFallback;
  final int reservedOutputTokens;
  final int systemTokens;
  final int toolTokens;
  final int summaryTokens;
  final int recentHistoryTokens;
  final int promptTokens;
  final int inputTokens;

  int get totalTokens => inputTokens + reservedOutputTokens;

  double get usageRatio {
    if (maxContextTokens <= 0) {
      return 1;
    }
    return totalTokens / maxContextTokens;
  }

  int get usagePercent => (usageRatio * 100).round();

  bool get exceedsWindow => totalTokens > maxContextTokens;

  bool get shouldWarn => usageRatio >= 0.7;

  bool get shouldCompress => usageRatio >= 0.85;

  ContextBudgetLevel get level {
    if (exceedsWindow) {
      return ContextBudgetLevel.exceeded;
    }
    if (usageRatio >= 0.85) {
      return ContextBudgetLevel.high;
    }
    if (usageRatio >= 0.7) {
      return ContextBudgetLevel.warning;
    }
    return ContextBudgetLevel.normal;
  }
}

enum ContextBudgetLevel { normal, warning, high, exceeded }

class ContextBudgetExceededException implements Exception {
  const ContextBudgetExceededException(this.snapshot);

  final ContextBudgetSnapshot snapshot;

  @override
  String toString() {
    return '当前上下文预计 ${snapshot.totalTokens} tokens，超过模型窗口 '
        '${snapshot.maxContextTokens} tokens。请缩短本轮输入、减少附件，或在模型设置中确认更大的上下文窗口。';
  }
}
