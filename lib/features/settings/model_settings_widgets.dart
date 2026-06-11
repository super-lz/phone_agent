part of 'model_settings_page.dart';

enum _SettingsStatusKind { info, success, error }

class _SettingsStatus {
  const _SettingsStatus._(this.kind, this.message);

  factory _SettingsStatus.info(String message) =>
      _SettingsStatus._(_SettingsStatusKind.info, message);

  factory _SettingsStatus.success(String message) =>
      _SettingsStatus._(_SettingsStatusKind.success, message);

  factory _SettingsStatus.error(String message) =>
      _SettingsStatus._(_SettingsStatusKind.error, message);

  final _SettingsStatusKind kind;
  final String message;
}

class _ProviderGroupSection extends StatelessWidget {
  const _ProviderGroupSection({
    required this.title,
    required this.providers,
    required this.selectedProviderId,
    required this.onSelected,
  });

  final String title;
  final List<ModelProviderConfig> providers;
  final String selectedProviderId;
  final ValueChanged<ModelProviderConfig> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            for (final provider in providers)
              _ProviderTile(
                provider: provider,
                selected: provider.id == selectedProviderId,
                onTap: () => onSelected(provider),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final ModelProviderConfig provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: colorScheme.primary.withValues(alpha: 0.08),
      leading: Icon(
        provider.group == ModelProviderGroup.aggregator
            ? Icons.hub_outlined
            : Icons.cloud_outlined,
        color: selected ? colorScheme.primary : null,
      ),
      title: Text(
        provider.vendorName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        provider.defaultModel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: colorScheme.primary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.provider});

  final ModelProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            provider.group == ModelProviderGroup.aggregator
                ? Icons.hub_outlined
                : Icons.cloud_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.vendorName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                provider.displayName,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        _ProtocolBadge(provider: provider),
      ],
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  const _ProtocolBadge({required this.provider});

  final ModelProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final label = switch (provider.apiProtocol) {
      ModelApiProtocol.openAiChatCompletions => 'OpenAI',
      ModelApiProtocol.anthropicMessages => 'Messages',
      ModelApiProtocol.unavailable => '待确认',
    };
    final color = provider.apiProtocol == ModelApiProtocol.unavailable
        ? Colors.orange
        : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProviderSummary extends StatelessWidget {
  const _ProviderSummary({required this.provider});

  final ModelProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryLine(
            icon: Icons.dns_outlined,
            text: provider.apiProtocol == ModelApiProtocol.unavailable
                ? 'Endpoint: 官方 API 地址待确认'
                : 'Endpoint: ${provider.baseUrl}',
          ),
          const SizedBox(height: 6),
          _SummaryLine(
            icon: Icons.psychology_outlined,
            text: '当前模型: ${provider.model}',
          ),
          const SizedBox(height: 6),
          _SummaryLine(
            icon: Icons.donut_large_outlined,
            text: _contextWindowText(provider),
          ),
          const SizedBox(height: 6),
          _SummaryLine(
            icon: Icons.build_outlined,
            text: provider.supportsTools ? '工具调用: 支持' : '工具调用: 当前关闭',
          ),
        ],
      ),
    );
  }

  String _contextWindowText(ModelProviderConfig provider) {
    final tokens = provider.effectiveMaxContextTokens;
    if (tokens == null) {
      return '上下文窗口: 未知，运行时按 32k 保守预算';
    }
    final source = provider.contextWindowOverrideTokens == null ? '内置' : '手动覆盖';
    return '上下文窗口: ${_formatTokens(tokens)} · $source';
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      final k = tokens / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k tokens';
    }
    return '$tokens tokens';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final _SettingsStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status.kind) {
      _SettingsStatusKind.success => Colors.green,
      _SettingsStatusKind.error => Colors.red,
      _SettingsStatusKind.info => Colors.blue,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade100),
      ),
      child: Text(
        status.message,
        style: TextStyle(fontSize: 13, color: color.shade700),
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.logFilePath});

  final String? logFilePath;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('诊断日志', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        logFilePath ?? '尚未初始化',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
