class ModelProviderConfig {
  const ModelProviderConfig({
    required this.id,
    required this.vendorName,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.defaultParameters,
  });

  final String id;
  final String vendorName;
  final String displayName;
  final Uri baseUrl;
  final String model;
  final Map<String, Object?> defaultParameters;

  Uri get chatCompletionsEndpoint => baseUrl.resolve('chat/completions');

  ModelProviderConfig copyWith({String? model}) {
    return ModelProviderConfig(
      id: id,
      vendorName: vendorName,
      displayName: displayName,
      baseUrl: baseUrl,
      model: model ?? this.model,
      defaultParameters: defaultParameters,
    );
  }
}

class ModelProviders {
  const ModelProviders._();

  static final aliyunBailianQwenFlash = ModelProviderConfig(
    id: 'aliyun_bailian_glm5',
    vendorName: '阿里云百炼',
    displayName: 'Qwen3.6 Flash',
    baseUrl: aliyunBailianBaseUrl,
    model: 'qwen3.6-flash-2026-04-16',
    defaultParameters: {
      'enable_thinking': false,
      'temperature': 1.0,
      'top_p': 0.95,
      'top_k': 20,
      'stream': true,
    },
  );

  static final aliyunBailianGlm5 = aliyunBailianQwenFlash;
  
  static final gemmaLocal = ModelProviderConfig(
    id: 'gemma_local',
    vendorName: '本地模型',
    displayName: 'Gemma 4 E4B (Local)',
    baseUrl: Uri.parse('local://gemma'),
    model: 'gemma-4-e4b-it-int4.litertlm',
    defaultParameters: {
      'temperature': 0.7,
      'top_k': 40,
      'max_tokens': 2048,
    },
  );

  static final aliyunBailianBaseUrl = Uri.parse(
    'https://dashscope.aliyuncs.com/compatible-mode/v1/',
  );

  static final all = [aliyunBailianQwenFlash, gemmaLocal];
}
