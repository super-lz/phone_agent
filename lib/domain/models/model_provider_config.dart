enum ModelProviderGroup { domestic, international, aggregator }

enum ModelApiProtocol { openAiChatCompletions, anthropicMessages, unavailable }

class ModelOption {
  const ModelOption({
    required this.name,
    this.description,
    this.maxContextTokens,
  });

  final String name;
  final String? description;
  final int? maxContextTokens;
}

class ModelProviderConfig {
  const ModelProviderConfig({
    required this.id,
    required this.vendorName,
    required this.displayName,
    required this.group,
    required this.baseUrl,
    required this.apiProtocol,
    required this.defaultModel,
    required this.modelOptions,
    required this.supportsTools,
    required this.model,
    required this.defaultParameters,
    this.defaultHeaders = const {},
    this.apiKeyHelpUrl,
    this.documentationUrl,
    this.maxContextTokens,
    this.contextWindowOverrideTokens,
  });

  final String id;
  final String vendorName;
  final String displayName;
  final ModelProviderGroup group;
  final Uri baseUrl;
  final ModelApiProtocol apiProtocol;
  final String defaultModel;
  final List<ModelOption> modelOptions;
  final bool supportsTools;
  final String model;
  final Map<String, Object?> defaultParameters;
  final Map<String, String> defaultHeaders;
  final Uri? apiKeyHelpUrl;
  final Uri? documentationUrl;
  final int? maxContextTokens;
  final int? contextWindowOverrideTokens;

  bool get requiresApiKey => true;

  bool get canRunConnectionTest => apiProtocol != ModelApiProtocol.unavailable;

  int? get defaultMaxTokens {
    final raw = defaultParameters['max_tokens'];
    if (raw is int && raw > 0) {
      return raw;
    }
    return null;
  }

  Uri get chatCompletionsEndpoint => baseUrl.resolve('chat/completions');

  Uri get anthropicMessagesEndpoint => baseUrl.resolve('v1/messages');

  int? get selectedModelMaxContextTokens {
    for (final option in modelOptions) {
      if (option.name == model) {
        return option.maxContextTokens;
      }
    }
    return null;
  }

  int? get effectiveMaxContextTokens {
    return contextWindowOverrideTokens ??
        selectedModelMaxContextTokens ??
        maxContextTokens;
  }

  bool get hasKnownContextWindow => effectiveMaxContextTokens != null;

  ModelProviderConfig copyWith({
    String? model,
    int? contextWindowOverrideTokens,
  }) {
    return ModelProviderConfig(
      id: id,
      vendorName: vendorName,
      displayName: displayName,
      group: group,
      baseUrl: baseUrl,
      apiProtocol: apiProtocol,
      defaultModel: defaultModel,
      modelOptions: modelOptions,
      supportsTools: supportsTools,
      model: model ?? this.model,
      defaultParameters: defaultParameters,
      defaultHeaders: defaultHeaders,
      apiKeyHelpUrl: apiKeyHelpUrl,
      documentationUrl: documentationUrl,
      maxContextTokens: maxContextTokens,
      contextWindowOverrideTokens:
          contextWindowOverrideTokens ?? this.contextWindowOverrideTokens,
    );
  }
}

class ModelProviders {
  const ModelProviders._();

  static final aliyunBailianQwenFlash = ModelProviderConfig(
    id: 'aliyun_bailian_glm5',
    vendorName: '阿里云百炼',
    displayName: 'Qwen3.6 Flash',
    group: ModelProviderGroup.domestic,
    baseUrl: aliyunBailianBaseUrl,
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'qwen3.6-flash-2026-04-16',
    modelOptions: const [
      ModelOption(name: 'qwen3.6-flash-2026-04-16', description: '默认快速模型'),
      ModelOption(name: 'qwen3.6-flash'),
      ModelOption(name: 'qwen3.6-plus'),
      ModelOption(name: 'qwen3.7-max'),
      ModelOption(name: 'qwen-plus'),
      ModelOption(name: 'qwen-turbo'),
    ],
    supportsTools: true,
    model: 'qwen3.6-flash-2026-04-16',
    defaultParameters: {
      'enable_thinking': false,
      'temperature': 1.0,
      'top_p': 0.95,
      'top_k': 20,
      'stream': true,
    },
    apiKeyHelpUrl: Uri.parse(
      'https://help.aliyun.com/zh/model-studio/get-api-key',
    ),
    documentationUrl: Uri.parse(
      'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope',
    ),
  );

  static final aliyunBailianGlm5 = aliyunBailianQwenFlash;

  static final aliyunBailianBaseUrl = Uri.parse(
    'https://dashscope.aliyuncs.com/compatible-mode/v1/',
  );

  static final deepSeek = ModelProviderConfig(
    id: 'deepseek',
    vendorName: 'DeepSeek',
    displayName: 'DeepSeek V4 Pro',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://api.deepseek.com/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'deepseek-v4-pro',
    modelOptions: const [
      ModelOption(name: 'deepseek-v4-pro'),
      ModelOption(name: 'deepseek-v4-flash'),
      ModelOption(name: 'deepseek-chat', description: '兼容旧模型名'),
      ModelOption(name: 'deepseek-reasoner', description: '兼容旧模型名'),
    ],
    supportsTools: true,
    model: 'deepseek-v4-pro',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://platform.deepseek.com/'),
    documentationUrl: Uri.parse('https://api-docs.deepseek.com/'),
  );

  static final moonshotKimi = ModelProviderConfig(
    id: 'moonshot_kimi',
    vendorName: 'Kimi / Moonshot',
    displayName: 'Kimi K2.6',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://api.moonshot.ai/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'kimi-k2.6',
    modelOptions: const [
      ModelOption(name: 'kimi-k2.6'),
      ModelOption(name: 'kimi-k2.6-turbo'),
      ModelOption(name: 'moonshot-v1-8k', maxContextTokens: 8192),
      ModelOption(name: 'moonshot-v1-32k', maxContextTokens: 32768),
      ModelOption(name: 'moonshot-v1-128k', maxContextTokens: 131072),
    ],
    supportsTools: true,
    model: 'kimi-k2.6',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://platform.kimi.ai/'),
    documentationUrl: Uri.parse(
      'https://platform.kimi.ai/docs/guide/start-using-kimi-api',
    ),
  );

  static final zhipuGlm = ModelProviderConfig(
    id: 'zhipu_glm',
    vendorName: '智谱 GLM',
    displayName: 'GLM-5.1',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://open.bigmodel.cn/api/paas/v4/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'glm-5.1',
    modelOptions: const [
      ModelOption(name: 'glm-5.1'),
      ModelOption(name: 'glm-4.7'),
      ModelOption(name: 'glm-4.6'),
      ModelOption(name: 'glm-4-flash'),
    ],
    supportsTools: true,
    model: 'glm-5.1',
    defaultParameters: const {'temperature': 0.9, 'top_p': 0.7},
    apiKeyHelpUrl: Uri.parse(
      'https://bigmodel.cn/usercenter/proj-mgmt/apikeys',
    ),
    documentationUrl: Uri.parse(
      'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction',
    ),
  );

  static final tencentHunyuan = ModelProviderConfig(
    id: 'tencent_hunyuan',
    vendorName: '腾讯混元',
    displayName: 'Hunyuan Turbos',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://api.hunyuan.cloud.tencent.com/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'hunyuan-turbos-latest',
    modelOptions: const [
      ModelOption(name: 'hunyuan-turbos-latest'),
      ModelOption(name: 'hunyuan-t1-latest'),
      ModelOption(name: 'hunyuan-lite'),
    ],
    supportsTools: true,
    model: 'hunyuan-turbos-latest',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse(
      'https://console.cloud.tencent.com/hunyuan/api-key',
    ),
    documentationUrl: Uri.parse(
      'https://cloud.tencent.com/document/product/1729/111007',
    ),
  );

  static final miniMax = ModelProviderConfig(
    id: 'minimax',
    vendorName: 'MiniMax',
    displayName: 'MiniMax-M3',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://api.minimaxi.com/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'MiniMax-M3',
    modelOptions: const [
      ModelOption(name: 'MiniMax-M3'),
      ModelOption(name: 'MiniMax-M2.7'),
      ModelOption(name: 'MiniMax-M2.7-highspeed'),
      ModelOption(name: 'MiniMax-M2.5'),
      ModelOption(name: 'MiniMax-M2.5-highspeed'),
      ModelOption(name: 'MiniMax-M2.1'),
      ModelOption(name: 'MiniMax-M2.1-highspeed'),
      ModelOption(name: 'MiniMax-M2'),
    ],
    supportsTools: true,
    model: 'MiniMax-M3',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse(
      'https://platform.minimaxi.com/user-center/basic-information/interface-key',
    ),
    documentationUrl: Uri.parse(
      'https://platform.minimaxi.com/docs/api-reference/text-openai-api',
    ),
  );

  static final xiaomiMimo = ModelProviderConfig(
    id: 'xiaomi_mimo',
    vendorName: '小米 MiMo',
    displayName: 'MiMo V2.5 Pro',
    group: ModelProviderGroup.domestic,
    baseUrl: Uri.parse('https://api.xiaomimimo.com/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'mimo-v2.5-pro',
    modelOptions: const [
      ModelOption(name: 'mimo-v2.5-pro', maxContextTokens: 1000000),
      ModelOption(name: 'mimo-v2.5', maxContextTokens: 1000000),
      ModelOption(name: 'mimo-v2-pro', maxContextTokens: 1000000),
      ModelOption(name: 'mimo-v2-omni', maxContextTokens: 1000000),
      ModelOption(name: 'mimo-v2-flash', maxContextTokens: 256000),
    ],
    supportsTools: true,
    model: 'mimo-v2.5-pro',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://platform.xiaomimimo.com/'),
    documentationUrl: Uri.parse('https://platform.xiaomimimo.com/docs'),
  );

  static final siliconFlow = ModelProviderConfig(
    id: 'siliconflow',
    vendorName: '硅基流动',
    displayName: 'SiliconFlow',
    group: ModelProviderGroup.aggregator,
    baseUrl: Uri.parse('https://api.siliconflow.cn/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'Pro/zai-org/GLM-4.7',
    modelOptions: const [
      ModelOption(name: 'Pro/zai-org/GLM-4.7'),
      ModelOption(name: 'deepseek-ai/DeepSeek-V3.2'),
      ModelOption(name: 'Qwen/Qwen3.5-72B-Instruct'),
    ],
    supportsTools: true,
    model: 'Pro/zai-org/GLM-4.7',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://cloud.siliconflow.cn/account/ak'),
    documentationUrl: Uri.parse(
      'https://docs.siliconflow.cn/cn/api-reference/chat-completions/chat-completions',
    ),
  );

  static final openAi = ModelProviderConfig(
    id: 'openai',
    vendorName: 'OpenAI',
    displayName: 'GPT-5.5',
    group: ModelProviderGroup.international,
    baseUrl: Uri.parse('https://api.openai.com/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'gpt-5.5',
    modelOptions: const [
      ModelOption(name: 'gpt-5.5'),
      ModelOption(name: 'gpt-5.4'),
      ModelOption(name: 'gpt-5.2'),
      ModelOption(name: 'gpt-4.1'),
      ModelOption(name: 'gpt-4o'),
    ],
    supportsTools: true,
    model: 'gpt-5.5',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://platform.openai.com/api-keys'),
    documentationUrl: Uri.parse(
      'https://platform.openai.com/docs/api-reference/authentication',
    ),
  );

  static final googleGemini = ModelProviderConfig(
    id: 'google_gemini',
    vendorName: 'Google Gemini',
    displayName: 'Gemini 3.5 Flash',
    group: ModelProviderGroup.international,
    baseUrl: Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/openai/',
    ),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'gemini-3.5-flash',
    modelOptions: const [
      ModelOption(name: 'gemini-3.5-flash'),
      ModelOption(name: 'gemini-3.5-pro'),
      ModelOption(name: 'gemini-2.5-flash'),
      ModelOption(name: 'gemini-2.5-pro'),
    ],
    supportsTools: true,
    model: 'gemini-3.5-flash',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://aistudio.google.com/apikey'),
    documentationUrl: Uri.parse('https://ai.google.dev/gemini-api/docs/openai'),
  );

  static final xAi = ModelProviderConfig(
    id: 'xai',
    vendorName: 'xAI',
    displayName: 'Grok 4.3',
    group: ModelProviderGroup.international,
    baseUrl: Uri.parse('https://api.x.ai/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'grok-4.3',
    modelOptions: const [
      ModelOption(name: 'grok-4.3'),
      ModelOption(name: 'grok-4.2'),
      ModelOption(name: 'grok-4'),
    ],
    supportsTools: true,
    model: 'grok-4.3',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://console.x.ai/'),
    documentationUrl: Uri.parse(
      'https://docs.x.ai/developers/rest-api-reference/inference',
    ),
  );

  static final mistral = ModelProviderConfig(
    id: 'mistral',
    vendorName: 'Mistral',
    displayName: 'Mistral Large',
    group: ModelProviderGroup.international,
    baseUrl: Uri.parse('https://api.mistral.ai/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'mistral-large-latest',
    modelOptions: const [
      ModelOption(name: 'mistral-large-latest'),
      ModelOption(name: 'mistral-medium-latest'),
      ModelOption(name: 'mistral-small-latest'),
    ],
    supportsTools: true,
    model: 'mistral-large-latest',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://console.mistral.ai/api-keys'),
    documentationUrl: Uri.parse('https://docs.mistral.ai/api/'),
  );

  static final anthropicClaude = ModelProviderConfig(
    id: 'anthropic_claude',
    vendorName: 'Anthropic Claude',
    displayName: 'Claude Opus',
    group: ModelProviderGroup.international,
    baseUrl: Uri.parse('https://api.anthropic.com/'),
    apiProtocol: ModelApiProtocol.anthropicMessages,
    defaultModel: 'claude-opus-4-6',
    modelOptions: const [
      ModelOption(name: 'claude-opus-4-6'),
      ModelOption(name: 'claude-sonnet-4-5'),
      ModelOption(name: 'claude-haiku-4-5'),
    ],
    supportsTools: false,
    model: 'claude-opus-4-6',
    defaultParameters: const {'max_tokens': 4096},
    defaultHeaders: const {'anthropic-version': '2023-06-01'},
    apiKeyHelpUrl: Uri.parse('https://console.anthropic.com/settings/keys'),
    documentationUrl: Uri.parse(
      'https://platform.claude.com/docs/en/api/overview',
    ),
  );

  static final openRouter = ModelProviderConfig(
    id: 'openrouter',
    vendorName: 'OpenRouter',
    displayName: 'OpenRouter',
    group: ModelProviderGroup.aggregator,
    baseUrl: Uri.parse('https://openrouter.ai/api/v1/'),
    apiProtocol: ModelApiProtocol.openAiChatCompletions,
    defaultModel: 'openai/gpt-5.2',
    modelOptions: const [
      ModelOption(name: 'openai/gpt-5.2'),
      ModelOption(name: 'anthropic/claude-opus-4.6'),
      ModelOption(name: 'google/gemini-3.5-flash'),
      ModelOption(name: 'x-ai/grok-4.3'),
      ModelOption(name: 'xiaomi/mimo-v2.5-pro'),
    ],
    supportsTools: true,
    model: 'openai/gpt-5.2',
    defaultParameters: const {},
    apiKeyHelpUrl: Uri.parse('https://openrouter.ai/settings/keys'),
    documentationUrl: Uri.parse(
      'https://openrouter.ai/docs/api/reference/overview',
    ),
  );

  static final all = [
    aliyunBailianQwenFlash,
    deepSeek,
    moonshotKimi,
    zhipuGlm,
    tencentHunyuan,
    miniMax,
    xiaomiMimo,
    siliconFlow,
    openAi,
    googleGemini,
    xAi,
    mistral,
    anthropicClaude,
    openRouter,
  ];

  static List<ModelProviderConfig> byGroup(ModelProviderGroup group) {
    return all
        .where((provider) => provider.group == group)
        .toList(growable: false);
  }

  static ModelProviderConfig byIdOrDefault(String? providerId) {
    for (final provider in all) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return aliyunBailianQwenFlash;
  }
}
