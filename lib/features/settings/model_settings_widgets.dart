part of 'model_settings_page.dart';

class _GemmaModelCard extends StatelessWidget {
  const _GemmaModelCard({
    required this.installed,
    required this.downloading,
    required this.downloadProgress,
    required this.modelName,
    required this.urlController,
    required this.hfTokenController,
    required this.onDownload,
    required this.onPickLocalFile,
  });

  final bool installed;
  final bool downloading;
  final int downloadProgress;
  final String modelName;
  final TextEditingController urlController;
  final TextEditingController hfTokenController;
  final VoidCallback onDownload;
  final VoidCallback onPickLocalFile;

  @override
  Widget build(BuildContext context) {
    if (installed) {
      return _GemmaInstalledCard(modelName: modelName);
    }
    return _GemmaInstallCard(
      downloading: downloading,
      downloadProgress: downloadProgress,
      urlController: urlController,
      hfTokenController: hfTokenController,
      onDownload: onDownload,
      onPickLocalFile: onPickLocalFile,
    );
  }
}

class _GemmaInstalledCard extends StatelessWidget {
  const _GemmaInstalledCard({required this.modelName});

  final String modelName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gemma 本地模型已就绪',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '模型文件: $modelName · 无需 API Key',
                  style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GemmaInstallCard extends StatelessWidget {
  const _GemmaInstallCard({
    required this.downloading,
    required this.downloadProgress,
    required this.urlController,
    required this.hfTokenController,
    required this.onDownload,
    required this.onPickLocalFile,
  });

  final bool downloading;
  final int downloadProgress;
  final TextEditingController urlController;
  final TextEditingController hfTokenController;
  final VoidCallback onDownload;
  final VoidCallback onPickLocalFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                '本地模型文件未下载',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            enabled: !downloading,
            decoration: const InputDecoration(
              labelText: '模型下载 URL',
              hintText: '输入模型的直接下载链接',
              prefixIcon: Icon(Icons.link_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hfTokenController,
            enabled: !downloading,
            decoration: const InputDecoration(
              labelText: 'Hugging Face Token (可选)',
              hintText: '若下载 Gated 模型请填写 Token',
              prefixIcon: Icon(Icons.token_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (downloading)
            _GemmaDownloadProgress(progress: downloadProgress)
          else
            _GemmaInstallActions(
              onDownload: onDownload,
              onPickLocalFile: onPickLocalFile,
            ),
        ],
      ),
    );
  }
}

class _GemmaDownloadProgress extends StatelessWidget {
  const _GemmaDownloadProgress({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress / 100.0),
        const SizedBox(height: 8),
        Text(
          '下载进度: $progress%',
          style: const TextStyle(fontSize: 12, color: Colors.orange),
        ),
      ],
    );
  }
}

class _GemmaInstallActions extends StatelessWidget {
  const _GemmaInstallActions({
    required this.onDownload,
    required this.onPickLocalFile,
  });

  final VoidCallback onDownload;
  final VoidCallback onPickLocalFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载并安装 Gemma 4 E4B 模型'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPickLocalFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('导入本地模型文件 (.litertlm)'),
          ),
        ),
      ],
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
            provider.isLocal
                ? '运行位置: 本机设备 · API Key: 不需要'
                : 'Endpoint: ${provider.baseUrl}',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
          ),
          if (provider.isLocal && provider.defaultMaxTokens != null) ...[
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
    return '上下文: 当前使用 $defaultTokens tokens · LiteRT-LM 上限 $maxContextTokens tokens';
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
