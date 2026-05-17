import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('aliyun bailian glm-5 uses openai-compatible defaults', () {
    final provider = ModelProviders.aliyunBailianGlm5;

    expect(provider.vendorName, '阿里云百炼');
    expect(provider.model, 'glm-5');
    expect(
      provider.chatCompletionsEndpoint.toString(),
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    );
    expect(provider.defaultParameters['enable_thinking'], isFalse);
    expect(provider.defaultParameters['temperature'], 1.0);
    expect(provider.defaultParameters['top_p'], 0.95);
    expect(provider.defaultParameters['top_k'], 20);
    expect(provider.defaultParameters['stream'], isTrue);
  });

  test('chat client has a finite request timeout', () {
    final client = OpenAiCompatibleChatClient();

    expect(client.requestTimeout, const Duration(seconds: 30));
  });
}
