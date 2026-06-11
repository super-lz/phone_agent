import 'package:flutter/material.dart';

import '../../../application/agent/context_budget.dart';

class ContextBudgetRing extends StatelessWidget {
  const ContextBudgetRing({required this.budget, super.key});

  final ContextBudgetSnapshot? budget;

  @override
  Widget build(BuildContext context) {
    final snapshot = budget;
    final color = _ringColor(snapshot);
    final value = snapshot == null
        ? 0.0
        : snapshot.usageRatio.clamp(0.0, 1.0).toDouble();
    return Tooltip(
      message: snapshot == null
          ? '上下文用量将在发送后显示'
          : '上下文 ${snapshot.usagePercent}%',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: snapshot == null ? null : () => _showDetails(context, snapshot),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                snapshot == null ? '--' : '${snapshot.usagePercent}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _ringColor(ContextBudgetSnapshot? snapshot) {
    return switch (snapshot?.level) {
      ContextBudgetLevel.exceeded => Colors.red,
      ContextBudgetLevel.high => Colors.deepOrange,
      ContextBudgetLevel.warning => Colors.amber.shade700,
      ContextBudgetLevel.normal => Colors.green,
      null => Colors.grey,
    };
  }

  void _showDetails(BuildContext context, ContextBudgetSnapshot snapshot) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('上下文用量', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _DetailLine(label: '模型', value: snapshot.modelName),
                _DetailLine(
                  label: '窗口',
                  value:
                      '${_formatTokens(snapshot.maxContextTokens)}'
                      '${snapshot.isConservativeFallback ? '（保守预算）' : ''}',
                ),
                _DetailLine(
                  label: '当前',
                  value:
                      '${_formatTokens(snapshot.totalTokens)} / '
                      '${_formatTokens(snapshot.maxContextTokens)}',
                ),
                _DetailLine(
                  label: '预留输出',
                  value: _formatTokens(snapshot.reservedOutputTokens),
                ),
                const SizedBox(height: 12),
                _BudgetBreakdown(snapshot: snapshot),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTokens(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k tokens';
    }
    return '$value tokens';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _BudgetBreakdown extends StatelessWidget {
  const _BudgetBreakdown({required this.snapshot});

  final ContextBudgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('系统提示', snapshot.systemTokens),
      ('工具 schema', snapshot.toolTokens),
      ('压缩摘要', snapshot.summaryTokens),
      ('近期对话', snapshot.recentHistoryTokens),
      ('本轮输入', snapshot.promptTokens),
    ];
    return Column(
      children: [
        for (final item in items)
          _BreakdownBar(
            label: item.$1,
            tokens: item.$2,
            maxTokens: snapshot.maxContextTokens,
          ),
      ],
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.label,
    required this.tokens,
    required this.maxTokens,
  });

  final String label;
  final int tokens;
  final int maxTokens;

  @override
  Widget build(BuildContext context) {
    final ratio = maxTokens <= 0 ? 0.0 : (tokens / maxTokens).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio.toDouble(),
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Text(
              _format(tokens),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _format(int value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return '$value';
  }
}
