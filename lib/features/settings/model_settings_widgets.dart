part of 'model_settings_page.dart';

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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                '厂商: ${provider.vendorName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Endpoint: ${provider.baseUrl}',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
          ),
          if (provider.defaultMaxTokens != null) ...[
            const SizedBox(height: 4),
            Text(
              _contextWindowText(provider),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _contextWindowText(ModelProviderConfig provider) {
    final maxContextTokens = provider.maxContextTokens;
    final defaultTokens = provider.defaultMaxTokens;
    if (maxContextTokens == null) {
      return '上下文: 当前使用 $defaultTokens tokens';
    }
    return '上下文: 当前使用 $defaultTokens tokens · 上限 $maxContextTokens tokens';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isError = message.contains('失败') || message.contains('不能为空');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? Colors.red.shade100 : Colors.green.shade100,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: isError ? Colors.red.shade700 : Colors.green.shade700,
        ),
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
