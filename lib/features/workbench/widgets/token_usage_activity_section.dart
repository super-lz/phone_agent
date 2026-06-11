import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../domain/usage/token_usage.dart';
import 'token_usage_format.dart';

enum TokenUsageView { daily, weekly, cumulative }

class TokenUsageActivitySection extends StatelessWidget {
  const TokenUsageActivitySection({
    required this.stats,
    required this.usageView,
    required this.onChanged,
    super.key,
  });

  final TokenUsageStats stats;
  final TokenUsageView usageView;
  final ValueChanged<TokenUsageView> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Token 活动',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SegmentedButton<TokenUsageView>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                side: WidgetStateProperty.all(BorderSide.none),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? const Color(0xFFEAF4FF)
                      : Colors.transparent;
                }),
              ),
              segments: const [
                ButtonSegment(value: TokenUsageView.daily, label: Text('每日')),
                ButtonSegment(value: TokenUsageView.weekly, label: Text('每周')),
                ButtonSegment(
                  value: TokenUsageView.cumulative,
                  label: Text('累计'),
                ),
              ],
              selected: {usageView},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _TokenHeatmap(stats: stats, usageView: usageView),
      ],
    );
  }
}

class _TokenHeatmap extends StatelessWidget {
  const _TokenHeatmap({required this.stats, required this.usageView});

  final TokenUsageStats stats;
  final TokenUsageView usageView;

  @override
  Widget build(BuildContext context) {
    final buckets = stats.dailyBuckets;
    final values = _valuesFor(buckets, usageView);
    final maxValue = values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    final firstDay = buckets.first.day;
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    final totalDays = buckets.last.day.difference(gridStart).inDays + 1;
    final weekCount = (totalDays / 7).ceil();
    const cell = 11.0;
    const gap = 5.0;
    final pitch = cell + gap;
    final width = weekCount * pitch;
    final valueByDay = {
      for (var index = 0; index < buckets.length; index += 1)
        buckets[index].day: values[index],
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var week = 0; week < weekCount; week += 1)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Column(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday += 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: _HeatmapCell(
                              day: gridStart.add(
                                Duration(days: week * 7 + weekday),
                              ),
                              valueByDay: valueByDay,
                              maxValue: maxValue,
                              size: cell,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              width: width,
              child: Stack(children: _monthLabels(buckets, gridStart, pitch)),
            ),
          ],
        ),
      ),
    );
  }

  List<int> _valuesFor(
    List<TokenUsageDailyBucket> buckets,
    TokenUsageView usageView,
  ) {
    if (usageView == TokenUsageView.daily) {
      return buckets.map((bucket) => bucket.tokens).toList(growable: false);
    }
    if (usageView == TokenUsageView.cumulative) {
      var running = 0;
      return buckets
          .map((bucket) {
            running += bucket.tokens;
            return running;
          })
          .toList(growable: false);
    }
    final weekly = <DateTime, int>{};
    for (final bucket in buckets) {
      final weekStart = _weekStart(bucket.day);
      weekly[weekStart] = (weekly[weekStart] ?? 0) + bucket.tokens;
    }
    return buckets
        .map((bucket) {
          return weekly[_weekStart(bucket.day)] ?? 0;
        })
        .toList(growable: false);
  }

  DateTime _weekStart(DateTime day) {
    return day.subtract(Duration(days: day.weekday - 1));
  }

  List<Widget> _monthLabels(
    List<TokenUsageDailyBucket> buckets,
    DateTime gridStart,
    double pitch,
  ) {
    final labels = <Widget>[];
    var previousMonth = -1;
    for (final bucket in buckets) {
      if (bucket.day.month == previousMonth) {
        continue;
      }
      previousMonth = bucket.day.month;
      final week = bucket.day.difference(gridStart).inDays ~/ 7;
      labels.add(
        Positioned(
          left: week * pitch,
          child: Text(
            '${bucket.day.month}月',
            style: const TextStyle(color: Color(0xFF8B8F95), fontSize: 13),
          ),
        ),
      );
    }
    return labels;
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.day,
    required this.valueByDay,
    required this.maxValue,
    required this.size,
  });

  final DateTime day;
  final Map<DateTime, int> valueByDay;
  final int maxValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = valueByDay[day];
    final color = _cellColor(value, maxValue);
    final label = value == null
        ? ''
        : '${day.month}月${day.day}日 · ${formatTokenCount(value)}';
    return Tooltip(
      message: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

Color _cellColor(int? value, int maxValue) {
  if (value == null || value <= 0 || maxValue <= 0) {
    return const Color(0xFFF0F0F1);
  }
  final ratio = value / maxValue;
  if (ratio >= 0.75) {
    return const Color(0xFF4FA9F8);
  }
  if (ratio >= 0.5) {
    return const Color(0xFF8CC8FB);
  }
  if (ratio >= 0.25) {
    return const Color(0xFFB9DBFA);
  }
  return const Color(0xFFD7EBFC);
}
