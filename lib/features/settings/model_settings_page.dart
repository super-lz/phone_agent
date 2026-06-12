import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _customModelValue = '__custom_model__';

  late final ModelApiKeyStore _apiKeyStore;
  late final ModelSettingsStore _modelSettingsStore;
  late final OpenAiCompatibleChatClient _chatClient;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _contextWindowController;
  late final TextEditingController _customModelController;

  ModelProviderConfig _provider = ModelProviders.aliyunBailianQwenFlash;
  String _selectedModelValue =
      ModelProviders.aliyunBailianQwenFlash.defaultModel;
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _testing = false;
  _SettingsStatus? _status;

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
    _contextWindowController = TextEditingController();
    _customModelController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _contextWindowController.dispose();
    _customModelController.dispose();
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
    final contextWindowTokens = await _modelSettingsStore
        .readContextWindowTokens(provider.id);
    final apiKey = await _apiKeyStore.readApiKey(provider.id);
    if (!mounted || _provider.id != provider.id) {
      return;
    }
    _apiKeyController.text = apiKey ?? '';
    _contextWindowController.text = contextWindowTokens?.toString() ?? '';
    _setSelectedModel(modelName?.trim(), provider: provider);
    setState(() => _loading = false);
  }

  void _setSelectedModel(
    String? modelName, {
    required ModelProviderConfig provider,
  }) {
    final normalized = modelName == null || modelName.isEmpty
        ? provider.defaultModel
        : modelName;
    final matchesPreset = provider.modelOptions.any(
      (option) => option.name == normalized,
    );
    _selectedModelValue = matchesPreset ? normalized : _customModelValue;
    _customModelController.text = matchesPreset ? '' : normalized;
  }

  Future<void> _saveSettings() async {
    final modelName = _currentModelName();
    if (modelName.isEmpty) {
      setState(() => _status = _SettingsStatus.error('模型名称不能为空。'));
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _status = _SettingsStatus.error('API Key 不能为空。'));
      return;
    }
    final contextWindowTokens = _currentContextWindowOverride();
    if (contextWindowTokens == 0) {
      setState(
        () =>
            _status = _SettingsStatus.error('最大上下文 token 必须是正整数，或留空使用内置/保守预算。'),
      );
      return;
    }

    await _modelSettingsStore.saveSelectedProviderId(_provider.id);
    await _apiKeyStore.saveApiKey(_provider.id, apiKey);
    await _modelSettingsStore.saveModelName(_provider.id, modelName);
    if (contextWindowTokens == null) {
      await _modelSettingsStore.deleteContextWindowTokens(_provider.id);
    } else {
      await _modelSettingsStore.saveContextWindowTokens(
        _provider.id,
        contextWindowTokens,
      );
    }
    if (!mounted) {
      return;
    }
    setState(
      () => _status = _SettingsStatus.success(
        '已保存 ${_provider.vendorName} / $modelName 的模型配置。',
      ),
    );
  }

  Future<void> _clearApiKey() async {
    await _apiKeyStore.deleteApiKey(_provider.id);
    if (!mounted) {
      return;
    }
    _apiKeyController.clear();
    setState(
      () => _status = _SettingsStatus.info(
        '已清除 ${_provider.vendorName} API Key。',
      ),
    );
  }

  Future<void> _restoreDefaultModel() async {
    await _modelSettingsStore.deleteModelName(_provider.id);
    await _modelSettingsStore.deleteContextWindowTokens(_provider.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _contextWindowController.clear();
      _setSelectedModel(_provider.defaultModel, provider: _provider);
      _status = _SettingsStatus.info('已恢复默认模型：${_provider.defaultModel}');
    });
  }

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _status = _SettingsStatus.error('请先填写 API Key。'));
      return;
    }
    final provider = _effectiveProvider();

    setState(() {
      _testing = true;
      _status = _SettingsStatus.info(
        '正在测试 ${provider.vendorName} / ${provider.model}，最多等待 15 秒...',
      );
    });

    final result = await _chatClient.testConnection(
      provider: provider,
      apiKey: apiKey,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _status = result.ok
          ? _SettingsStatus.success(result.message)
          : _SettingsStatus.error('连接失败：${result.message}');
    });
  }

  Future<void> _setProvider(ModelProviderConfig provider) async {
    if (provider.id == _provider.id) {
      return;
    }
    setState(() {
      _provider = provider;
      _setSelectedModel(provider.defaultModel, provider: provider);
      _contextWindowController.clear();
      _loading = true;
      _status = _SettingsStatus.info('已选择 ${provider.vendorName}。');
    });
    await _modelSettingsStore.saveSelectedProviderId(provider.id);
    await _loadProviderSettings();
  }

  Future<void> _openUri(Uri? uri) async {
    if (uri == null) {
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _status = _SettingsStatus.error('无法打开链接：$uri'));
    }
  }

  String _currentModelName() {
    if (_selectedModelValue == _customModelValue) {
      return _customModelController.text.trim();
    }
    return _selectedModelValue.trim();
  }

  ModelProviderConfig _effectiveProvider() {
    final modelName = _currentModelName();
    final contextWindowTokens = _currentContextWindowOverride();
    return _provider.copyWith(
      model: modelName.isEmpty ? _provider.model : modelName,
      contextWindowOverrideTokens: contextWindowTokens == 0
          ? null
          : contextWindowTokens,
    );
  }

  int? _currentContextWindowOverride() {
    final raw = _contextWindowController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      return 0;
    }
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(title: const Text('模型设置')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final content = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: _providerList()),
                    const SizedBox(width: 16),
                    Expanded(child: _configurationPanel()),
                  ],
                )
              : Column(
                  children: [
                    _providerList(),
                    const SizedBox(height: 16),
                    _configurationPanel(),
                  ],
                );
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [content, const SizedBox(height: 32)],
          );
        },
      ),
    );
  }

  Widget _providerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('模型提供方'),
        for (final group in ModelProviderGroup.values) ...[
          _ProviderGroupSection(
            title: _groupTitle(group),
            providers: ModelProviders.byGroup(group),
            selectedProviderId: _provider.id,
            onSelected: _setProvider,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _configurationPanel() {
    final provider = _provider;
    final modelOptions = _uniqueModelOptions(provider.modelOptions);
    final selectedModelValue = _dropdownModelValue(
      selectedValue: _selectedModelValue,
      options: modelOptions,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('连接配置'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProviderHeader(provider: provider),
                const SizedBox(height: 16),
                _ProviderSummary(provider: _effectiveProvider()),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  enabled: !_loading,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: '${provider.vendorName} API Key',
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
                DropdownButtonFormField<String>(
                  initialValue: selectedModelValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    prefixIcon: Icon(Icons.psychology_outlined),
                  ),
                  items: [
                    for (final option in modelOptions)
                      DropdownMenuItem(
                        value: option.name,
                        child: Text(
                          option.description == null
                              ? option.name
                              : '${option.name} · ${option.description}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const DropdownMenuItem(
                      value: _customModelValue,
                      child: Text('自定义模型名称'),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedModelValue = value);
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contextWindowController,
                  enabled: !_loading,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最大上下文 token（可选）',
                    hintText: '留空使用内置窗口；未知模型按保守预算',
                    prefixIcon: Icon(Icons.donut_large_outlined),
                  ),
                  onChanged: (_) {
                    setState(() {});
                  },
                ),
                if (_selectedModelValue == _customModelValue) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _customModelController,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: '自定义模型名称',
                      hintText: '输入接入方文档中的模型 ID',
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _saveSettings,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('保存配置'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading || _testing
                          ? null
                          : provider.canRunConnectionTest
                          ? _testConnection
                          : null,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 18),
                      label: Text(_testing ? '测试中...' : '连接测试'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _restoreDefaultModel,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('默认模型'),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : _clearApiKey,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清除 Key'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openUri(provider.apiKeyHelpUrl),
                      icon: const Icon(Icons.vpn_key_outlined, size: 18),
                      label: const Text('获取 Key'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openUri(provider.documentationUrl),
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('接口文档'),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  _StatusCard(status: _status!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('其他'),
        Card(child: _DiagnosticsSection(logFilePath: AppLogger.logFilePath)),
      ],
    );
  }

  List<ModelOption> _uniqueModelOptions(List<ModelOption> options) {
    final byName = <String, ModelOption>{};
    for (final option in options) {
      byName.putIfAbsent(option.name, () => option);
    }
    return byName.values.toList(growable: false);
  }

  String _dropdownModelValue({
    required String selectedValue,
    required List<ModelOption> options,
  }) {
    if (selectedValue == _customModelValue) {
      return _customModelValue;
    }
    final hasSelected = options.any((option) => option.name == selectedValue);
    if (hasSelected) {
      return selectedValue;
    }
    return _customModelValue;
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

  String _groupTitle(ModelProviderGroup group) {
    return switch (group) {
      ModelProviderGroup.domestic => '国内模型',
      ModelProviderGroup.international => '国外模型',
      ModelProviderGroup.aggregator => '聚合平台',
    };
  }
}
