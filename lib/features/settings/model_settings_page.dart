import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
  late final TextEditingController _gemmaUrlController;
  late final TextEditingController _hfTokenController;

  ModelProviderConfig _provider = ModelProviders.aliyunBailianQwenFlash;
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _testing = false;
  String? _status;

  bool _gemmaInstalled = false;
  bool _downloading = false;
  int _downloadProgress = 0;

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
    _gemmaUrlController = TextEditingController(
      text:
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-int4.litertlm',
    );
    _hfTokenController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _gemmaUrlController.dispose();
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _checkGemmaStatus() async {
    try {
      final providerId = _provider.id;
      final installedModels = await FlutterGemma.listInstalledModels();
      if (!mounted || _provider.id != providerId) {
        return;
      }
      if (installedModels.isNotEmpty) {
        final activeModel = installedModels.first;
        setState(() {
          _gemmaInstalled = true;
          _modelController.text = activeModel;
        });
        await _modelSettingsStore.saveModelName(providerId, activeModel);
      } else {
        setState(() {
          _gemmaInstalled = false;
        });
      }
    } catch (_) {}
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

    if (provider.isLocal) {
      _apiKeyController.text = '';
      await _checkGemmaStatus();
      setState(() => _loading = false);
      return;
    }

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
    if (_provider.isLocal) {
      await _modelSettingsStore.saveModelName(_provider.id, modelName);
      if (!mounted) return;
      setState(() {
        _status = _gemmaInstalled
            ? '已使用本地模型。普通对话不会要求 API Key。'
            : '已切换到本地模型。普通对话不会要求 API Key；请先下载或导入模型文件。';
      });
      return;
    }

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

  Future<void> _downloadGemma() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _status = '正在启动下载...';
    });
    try {
      await FlutterGemma.initialize();
    } catch (e) {
      AppLogger.error('settings.gemma_init_failed', {'error': e.toString()});
      setState(() {
        _downloading = false;
        _status =
            '初始化失败: $e\n提示：如果您刚刚加入插件，请务必进行 Hot Restart (热重启) 或重新运行编译 App！';
      });
      return;
    }
    try {
      final url = _gemmaUrlController.text.trim();
      final token = _hfTokenController.text.trim();
      await FlutterGemma.installModel(modelType: ModelType.gemma4)
          .fromNetwork(url, token: token.isEmpty ? null : token)
          .withProgress((progress) {
            setState(() {
              _downloadProgress = progress;
              _status = '正在下载模型: $progress%';
            });
          })
          .install();
      await _modelSettingsStore.saveSelectedProviderId(_provider.id);
      await _checkGemmaStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _gemmaInstalled = true;
        _downloading = false;
        _status = '模型下载并安装成功。普通对话将使用本地模型，无需 API Key。';
      });
    } catch (e) {
      setState(() {
        _downloading = false;
        _status = '下载失败: $e';
      });
    }
  }

  Future<void> _pickAndInstallLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) {
        return;
      }
      final filePath = result.files.first.path;
      if (filePath == null) {
        setState(() => _status = '无法获取选定文件的路径。');
        return;
      }

      setState(() {
        _downloading = true;
        _status = '正在从本地文件导入模型...';
      });

      try {
        await FlutterGemma.initialize();
      } catch (_) {}

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
      ).fromFile(filePath).install();

      await _modelSettingsStore.saveSelectedProviderId(_provider.id);
      await _checkGemmaStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _gemmaInstalled = true;
        _downloading = false;
        _status = '本地模型文件导入并激活成功。普通对话将使用本地模型，无需 API Key。';
      });
    } catch (e) {
      setState(() {
        _downloading = false;
        _status = '导入模型文件失败: $e';
      });
    }
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
      _status = _provider.isLocal
          ? '正在检查本地模型...'
          : '正在测试 ${_provider.displayName}，最多等待 15 秒...';
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
      _status = provider.isLocal
          ? '已切换到本地模型：普通对话不会要求 API Key。'
          : '已选择${provider.vendorName}：普通对话需要 API Key。';
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
                      icon: Icon(
                        provider.id == 'gemma_local'
                            ? Icons.phone_android_outlined
                            : Icons.cloud_outlined,
                        size: 18,
                      ),
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
                      labelText: _provider.isLocal ? '本地模型文件名' : '云端模型名称',
                      hintText: _provider.isLocal
                          ? '例如 gemma-4-e4b-it-int4.litertlm'
                          : '例如 qwen3.6-flash',
                      prefixIcon: const Icon(Icons.psychology_outlined),
                      suffixIcon: IconButton(
                        tooltip: '恢复默认',
                        icon: const Icon(Icons.restore, size: 20),
                        onPressed: _loading ? null : _restoreDefaultModel,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_provider.requiresApiKey) ...[
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
                  ] else ...[
                    _GemmaModelCard(
                      installed: _gemmaInstalled,
                      downloading: _downloading,
                      downloadProgress: _downloadProgress,
                      modelName: _modelController.text.trim(),
                      urlController: _gemmaUrlController,
                      hfTokenController: _hfTokenController,
                      onDownload: _downloadGemma,
                      onPickLocalFile: _pickAndInstallLocalFile,
                    ),
                    const SizedBox(height: 16),
                  ],
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
                if (_provider.requiresApiKey) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: const Text(
                      '清除当前 API Key',
                      style: TextStyle(color: Colors.red, fontSize: 14),
                    ),
                    onTap: _loading ? null : _clearApiKey,
                  ),
                  const Divider(height: 1, indent: 56),
                ],
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
