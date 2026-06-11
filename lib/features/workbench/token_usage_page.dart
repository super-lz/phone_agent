import 'package:flutter/material.dart';

import '../../app/phone_agent_colors.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/usage/token_usage.dart';
import '../../domain/workbench/workbench_store.dart';
import 'widgets/token_usage_activity_section.dart';
import 'widgets/token_usage_profile_widgets.dart';

class TokenUsagePage extends StatefulWidget {
  const TokenUsagePage({required this.workbenchStore, super.key});

  final WorkbenchStore workbenchStore;

  @override
  State<TokenUsagePage> createState() => _TokenUsagePageState();
}

class _TokenUsagePageState extends State<TokenUsagePage> {
  late Future<_TokenUsagePageData> _dataFuture;
  TokenUsageView _usageView = TokenUsageView.daily;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_TokenUsagePageData> _loadData() async {
    final records = await widget.workbenchStore.loadTokenUsageRecords();
    final invocations = await widget.workbenchStore.loadInvocations();
    return _TokenUsagePageData(
      stats: TokenUsageStats.fromRecords(records),
      topCapabilities: _topCapabilities(invocations),
    );
  }

  void _reload() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Token 用量'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_TokenUsagePageData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            children: [
              TokenUsageHeader(stats: data.stats),
              const SizedBox(height: 32),
              TokenUsageSummaryStrip(stats: data.stats),
              const SizedBox(height: 44),
              TokenUsageActivitySection(
                stats: data.stats,
                usageView: _usageView,
                onChanged: (view) => setState(() => _usageView = view),
              ),
              const SizedBox(height: 44),
              _ResponsiveDetails(data: data),
              if (data.stats.totalRuns == 0) ...[
                const SizedBox(height: 40),
                Text(
                  '完成一次模型对话后，这里会开始展示本机估算的 Token 用量。',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ResponsiveDetails extends StatelessWidget {
  const _ResponsiveDetails({required this.data});

  final _TokenUsagePageData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final insights = TokenUsageInsightSection(stats: data.stats);
        final models = TokenUsageModelUsageSection(
          stats: data.stats,
          capabilities: data.topCapabilities,
        );
        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [insights, const SizedBox(height: 28), models],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: insights),
            SizedBox(width: constraints.maxWidth * 0.12),
            Expanded(child: models),
          ],
        );
      },
    );
  }
}

class _TokenUsagePageData {
  const _TokenUsagePageData({
    required this.stats,
    required this.topCapabilities,
  });

  final TokenUsageStats stats;
  final List<CapabilityUsageCount> topCapabilities;
}

List<CapabilityUsageCount> _topCapabilities(
  List<CapabilityInvocation> invocations,
) {
  final counts = <String, int>{};
  for (final invocation in invocations) {
    counts[invocation.capabilityId] =
        (counts[invocation.capabilityId] ?? 0) + 1;
  }
  final rows =
      counts.entries
          .map(
            (entry) => CapabilityUsageCount(
              capabilityId: entry.key,
              count: entry.value,
            ),
          )
          .toList(growable: false)
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) {
            return byCount;
          }
          return a.capabilityId.compareTo(b.capabilityId);
        });
  return rows;
}
