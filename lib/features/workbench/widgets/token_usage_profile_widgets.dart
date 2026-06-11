import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../domain/usage/token_usage.dart';
import 'token_usage_format.dart';

class TokenUsageHeader extends StatelessWidget {
  const TokenUsageHeader({required this.stats, super.key});

  final TokenUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Column(
      children: [
        Text(
          'Phone Agent',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '本机估算',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${stats.totalRuns} 次运行',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TokenUsageSummaryStrip extends StatelessWidget {
  const TokenUsageSummaryStrip({required this.stats, super.key});

  final TokenUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryItem('累计 Token 数', formatTokenCount(stats.totalTokens)),
      _SummaryItem('峰值 Token 数', formatTokenCount(stats.peakRunTokens)),
      _SummaryItem('最长任务时长', formatTokenDuration(stats.longestDuration)),
      _SummaryItem('当前连续天数', '${stats.currentStreakDays} 天'),
      _SummaryItem('最长连续天数', '${stats.longestStreakDays} 天'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEDEFF2)),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Wrap(
              runSpacing: 18,
              children: [
                for (final item in items)
                  SizedBox(
                    width: constraints.maxWidth / 2,
                    child: _SummaryMetric(item: item),
                  ),
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < items.length; index += 1) ...[
                Expanded(child: _SummaryMetric(item: items[index])),
                if (index != items.length - 1)
                  const SizedBox(
                    height: 44,
                    child: VerticalDivider(color: Color(0xFFEDEFF2)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class TokenUsageInsightSection extends StatelessWidget {
  const TokenUsageInsightSection({required this.stats, super.key});

  final TokenUsageStats stats;

  @override
  Widget build(BuildContext context) {
    return _SectionBlock(
      title: '用量洞察',
      children: [
        _InsightRow('平均每次 Token', formatTokenCount(stats.averageTokensPerRun)),
        _InsightRow('已记录任务', '${stats.totalRuns} 次'),
        _InsightRow(
          '保守预算占比',
          '${(stats.conservativeEstimateRatio * 100).round()}%',
        ),
      ],
    );
  }
}

class TokenUsageModelUsageSection extends StatelessWidget {
  const TokenUsageModelUsageSection({
    required this.stats,
    required this.capabilities,
    super.key,
  });

  final TokenUsageStats stats;
  final List<CapabilityUsageCount> capabilities;

  @override
  Widget build(BuildContext context) {
    final modelRows = stats.modelBuckets
        .take(3)
        .map((bucket) {
          return _RankRow(
            icon: Icons.memory_outlined,
            title: bucket.name,
            trailing: '${bucket.runCount} 次',
          );
        })
        .toList(growable: false);
    final capabilityRows = capabilities
        .take(2)
        .map((capability) {
          return _RankRow(
            icon: Icons.extension_outlined,
            title: capability.capabilityId,
            trailing: '${capability.count} 次',
          );
        })
        .toList(growable: false);
    return _SectionBlock(
      title: '最常用的模型',
      children: [
        if (modelRows.isEmpty) const _EmptyLine('暂无模型用量记录') else ...modelRows,
        if (capabilityRows.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '常用能力',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: context.phoneAgentColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...capabilityRows,
        ],
      ],
    );
  }
}

class CapabilityUsageCount {
  const CapabilityUsageCount({required this.capabilityId, required this.count});

  final String capabilityId;
  final int count;
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFEDEFF2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: colors.primaryAction),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trailing,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: context.phoneAgentColors.textSecondary,
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value);

  final String label;
  final String value;
}
