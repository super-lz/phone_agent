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
}

class ModelProviders {
  const ModelProviders._();

  static final aliyunBailianGlm5 = ModelProviderConfig(
    id: 'aliyun_bailian_glm5',
    vendorName: '阿里云百炼',
    displayName: 'GLM-5',
    baseUrl: aliyunBailianBaseUrl,
    model: 'glm-5',
    defaultParameters: {
      'enable_thinking': false,
      'temperature': 1.0,
      'top_p': 0.95,
      'top_k': 20,
      'stream': true,
    },
  );

  static final aliyunBailianBaseUrl = Uri.parse(
    'https://dashscope.aliyuncs.com/compatible-mode/v1/',
  );

  static final all = [aliyunBailianGlm5];
}
