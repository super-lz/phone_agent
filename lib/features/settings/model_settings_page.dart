import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/model_api_key_store.dart';
import '../../data/models/model_settings_store.dart';
import '../../data/models/openai_compatible_chat_client.dart';
import '../../domain/models/model_provider_config.dart';

part 'model_settings_widgets.dart';

class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({
    super.key,
    this.apiKeyStore,
    this.modelSettingsStore,
    this.chatClient,
  });

  final ModelApiKeyStore? apiKeyStore;
  final ModelSettingsStore? modelSettingsStore;
  final OpenAiCompatibleChatClient? chatClient;

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage> {
  late final ModelApiKeyStore _apiKeyStore;
  late final ModelSettingsStore _modelSettingsStore;
  late final OpenAiCompatibleChatClient _chatClient;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;

  ModelProviderConfig _provider = ModelProviders.aliyunBailianQwenFlash;
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _testing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _apiKeyStore = widget.apiKeyStore ?? ModelApiKeyStore();
    _modelSettingsStore =
        widget.modelSettingsStore ?? SecureModelSettingsStore();
    _chatClient =
        widget.chatClient ??
        OpenAiCompatibleChatClient(requestTimeout: const Duration(seconds: 15));
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final selectedProviderId = await _modelSettingsStore
        .readSelectedProviderId();
    if (!mounted) {
      return;
    }
    _provider = ModelProviders.byIdOrDefault(selectedProviderId);
    await _loadProviderSettings();
  }

  Future<void> _loadProviderSettings() async {
    final provider = _provider;
    final modelName = await _modelSettingsStore.readModelName(provider.id);
    if (!mounted || _provider.id != provider.id) {
      return;
    }
    _modelController.text = modelName?.trim().isNotEmpty == true
        ? modelName!.trim()
        : provider.model;

    final apiKey = await _apiKeyStore.readApiKey(provider.id);
    if (!mounted) {
      return;
    }
    _apiKeyController.text = apiKey ?? '';
    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    final modelName = _modelController.text.trim();
    if (modelName.isEmpty) {
      setState(() => _status = '模型名称不能为空。');
      return;
    }

    await _modelSettingsStore.saveSelectedProviderId(_provider.id);
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _status = 'API Key 不能为空。');
      return;
    }
    await _apiKeyStore.saveApiKey(_provider.id, apiKey);
    await _modelSettingsStore.saveModelName(_provider.id, modelName);
    if (!mounted) {
      return;
    }
    setState(() => _status = '已保存 ${_provider.vendorName} API Key 和模型名称。');
  }

  Future<void> _clearApiKey() async {
    await _apiKeyStore.deleteApiKey(_provider.id);
    if (!mounted) {
      return;
    }
    _apiKeyController.clear();
    setState(() => _status = '已清除 API Key。');
  }

  Future<void> _restoreDefaultModel() async {
    await _modelSettingsStore.deleteModelName(_provider.id);
    if (!mounted) {
      return;
    }
    _modelController.text = _provider.model;
    setState(() => _status = '已恢复默认模型：${_provider.model}');
  }

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    if (_provider.requiresApiKey && apiKey.isEmpty) {
      setState(() => _status = '请先填写 API Key。');
      return;
    }

    setState(() {
      _testing = true;
      _status = '正在测试 ${_provider.displayName}，最多等待 15 秒...';
    });

    final provider = _effectiveProvider();
    final result = await _chatClient.testConnection(
      provider: provider,
      apiKey: apiKey,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _status = result.ok ? '测试成功：${result.message}' : '测试失败：${result.message}';
    });
  }

  Future<void> _setProvider(ModelProviderConfig provider) async {
    if (provider.id == _provider.id) {
      return;
    }
    setState(() {
      _provider = provider;
      _loading = true;
      _status = '已选择${provider.vendorName}：普通对话需要 API Key。';
    });
    await _modelSettingsStore.saveSelectedProviderId(provider.id);
    await _loadProviderSettings();
  }

  ModelProviderConfig _effectiveProvider() {
    final modelName = _modelController.text.trim();
    if (modelName.isEmpty || modelName == _provider.model) {
      return _provider;
    }
    return _provider.copyWith(model: modelName);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(title: const Text('模型设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader('模型提供方'),
          Card(
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SegmentedButton<ModelProviderConfig>(
                style: SegmentedButton.styleFrom(
                  side: BorderSide.none,
                  backgroundColor: Colors.transparent,
                  selectedBackgroundColor: colorScheme.primary,
                  selectedForegroundColor: colorScheme.onPrimary,
                ),
                segments: [
                  for (final provider in ModelProviders.all)
                    ButtonSegment(
                      value: provider,
                      label: Text(provider.vendorName),
                      icon: const Icon(Icons.cloud_outlined, size: 18),
                    ),
                ],
                selected: {_provider},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _setProvider(selection.first),
              ),
            ),
          ),
          _buildSectionHeader('连接配置'),
          Card(
            margin: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _modelController,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      labelText: '云端模型名称',
                      hintText: '例如 qwen3.6-flash',
                      prefixIcon: const Icon(Icons.psychology_outlined),
                      suffixIcon: IconButton(
                        tooltip: '恢复默认',
                        icon: const Icon(Icons.restore, size: 20),
                        onPressed: _loading ? null : _restoreDefaultModel,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    enabled: !_loading,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: '${_provider.vendorName} API Key',
                      hintText: '输入您的 API 密钥',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: _obscureApiKey ? '显示' : '隐藏',
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _obscureApiKey = !_obscureApiKey);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ProviderSummary(provider: _effectiveProvider()),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _saveSettings,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('保存配置'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading || _testing
                              ? null
                              : _testConnection,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.network_check, size: 18),
                          label: Text(_testing ? '测试中...' : '连接测试'),
                        ),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    _StatusCard(message: _status!),
                  ],
                ],
              ),
            ),
          ),
          _buildSectionHeader('其他'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    '清除当前 API Key',
                    style: TextStyle(color: Colors.red, fontSize: 14),
                  ),
                  onTap: _loading ? null : _clearApiKey,
                ),
                const Divider(height: 1, indent: 56),
                _DiagnosticsSection(logFilePath: AppLogger.logFilePath),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
