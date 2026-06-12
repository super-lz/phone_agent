import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/context_budget.dart';

class ContextBudgetRing extends StatelessWidget {
  const ContextBudgetRing({required this.budget, super.key});

  final ContextBudgetSnapshot? budget;

  static const _tapSize = 40.0;
  static const _ringSize = 30.0;
  static const _idleIconSize = 22.0;
  static const _labelWidth = 22.0;
  static const _labelHeight = 12.0;

  @override
  Widget build(BuildContext context) {
    final snapshot = budget;
    final color = _ringColor(snapshot);
    final usageLabel = _usageLabel(snapshot);
    final value = snapshot == null
        ? 0.0
        : snapshot.usageRatio.clamp(0.0, 1.0).toDouble();
    return Tooltip(
      message: snapshot == null ? '上下文用量待计算' : '上下文 $usageLabel',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: snapshot == null ? null : () => _showDetails(context, snapshot),
        child: SizedBox(
          width: _tapSize,
          height: _tapSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: _ringSize,
                height: _ringSize,
                child: CustomPaint(
                  painter: _ContextBudgetRingPainter(
                    value: value,
                    color: color,
                    trackColor: _trackColor(context),
                    strokeWidth: 3,
                  ),
                ),
              ),
              if (snapshot == null)
                Icon(
                  Icons.donut_large_outlined,
                  size: _idleIconSize,
                  color: color.withValues(alpha: 0.72),
                )
              else
                SizedBox(
                  width: _labelWidth,
                  height: _labelHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      usageLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
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
      null => const Color(0xFF9AA6B2),
    };
  }

  Color _trackColor(BuildContext context) {
    return context.phoneAgentColors.textTertiary.withValues(alpha: 0.48);
  }

  String _usageLabel(ContextBudgetSnapshot? snapshot) {
    if (snapshot == null) {
      return '';
    }
    if (snapshot.usagePercent <= 0) {
      return '<1%';
    }
    return '${snapshot.usagePercent}%';
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

class _ContextBudgetRingPainter extends CustomPainter {
  const _ContextBudgetRingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (value <= 0) {
      return;
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ContextBudgetRingPainter oldDelegate) {
    return value != oldDelegate.value ||
        color != oldDelegate.color ||
        trackColor != oldDelegate.trackColor ||
        strokeWidth != oldDelegate.strokeWidth;
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
