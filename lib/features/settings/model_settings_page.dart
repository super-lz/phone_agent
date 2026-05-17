import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/model_api_key_store.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/models/model_provider_config.dart';

class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({super.key, this.apiKeyStore, this.chatClient});

  final ModelApiKeyStore? apiKeyStore;
  final OpenAiCompatibleChatClient? chatClient;

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage> {
  late final ModelApiKeyStore _apiKeyStore;
  late final OpenAiCompatibleChatClient _chatClient;
  late final TextEditingController _apiKeyController;
  ModelProviderConfig _provider = ModelProviders.aliyunBailianQwenFlash;
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _testing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _apiKeyStore = widget.apiKeyStore ?? ModelApiKeyStore();
    _chatClient =
        widget.chatClient ??
        OpenAiCompatibleChatClient(requestTimeout: const Duration(seconds: 15));
    _apiKeyController = TextEditingController();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final apiKey = await _apiKeyStore.readApiKey(_provider.id);
    if (!mounted) {
      return;
    }
    _apiKeyController.text = apiKey ?? '';
    setState(() => _loading = false);
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _status = 'API Key 不能为空。');
      return;
    }
    await _apiKeyStore.saveApiKey(_provider.id, apiKey);
    if (!mounted) {
      return;
    }
    setState(() => _status = '已保存 ${_provider.vendorName} API Key。');
  }

  Future<void> _clearApiKey() async {
    await _apiKeyStore.deleteApiKey(_provider.id);
    if (!mounted) {
      return;
    }
    _apiKeyController.clear();
    setState(() => _status = '已清除 API Key。');
  }

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _status = '请先填写 API Key。');
      return;
    }

    setState(() {
      _testing = true;
      _status = '正在测试 ${_provider.displayName}，最多等待 15 秒...';
    });

    final result = await _chatClient.testConnection(
      provider: _provider,
      apiKey: apiKey,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _status = result.ok ? '连接成功：${result.message}' : '连接失败：${result.message}';
    });
  }

  void _setProvider(ModelProviderConfig provider) {
    if (provider.id == _provider.id) {
      return;
    }
    setState(() {
      _provider = provider;
      _loading = true;
      _status = null;
    });
    _loadApiKey();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('模型厂商', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ModelProviderConfig>(
            segments: [
              for (final provider in ModelProviders.all)
                ButtonSegment(
                  value: provider,
                  label: Text(provider.vendorName),
                  icon: const Icon(Icons.cloud_outlined),
                ),
            ],
            selected: {_provider},
            onSelectionChanged: (selection) => _setProvider(selection.first),
          ),
          const SizedBox(height: 16),
          _ProviderSummary(provider: _provider),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            enabled: !_loading,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: '${_provider.vendorName} API Key',
              helperText: '当前只需要填写 API Key，其它参数使用推荐默认值。',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                icon: Icon(
                  _obscureApiKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () {
                  setState(() => _obscureApiKey = !_obscureApiKey);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
                onPressed: _loading ? null : _saveApiKey,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.network_check),
                label: Text(_testing ? '测试中...' : '测试连接'),
                onPressed: _loading || _testing ? null : _testConnection,
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除'),
                onPressed: _loading ? null : _clearApiKey,
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            _StatusCard(message: _status!),
          ],
          const SizedBox(height: 24),
          _DiagnosticsSection(logFilePath: AppLogger.logFilePath),
        ],
      ),
    );
  }
}

class _ProviderSummary extends StatelessWidget {
  const _ProviderSummary({required this.provider});

  final ModelProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('模型', provider.model),
      ('Base URL', provider.baseUrl.toString()),
      ('默认参数', provider.defaultParameters.toString()),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.displayName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${entry.$1}: ${entry.$2}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.logFilePath});

  final String? logFilePath;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('诊断日志', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(logFilePath ?? '日志文件尚未初始化。'),
          ],
        ),
      ),
    );
  }
}
