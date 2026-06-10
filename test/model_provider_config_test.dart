import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('aliyun bailian qwen flash uses openai-compatible defaults', () {
    final provider = ModelProviders.aliyunBailianQwenFlash;

    expect(provider.vendorName, '阿里云百炼');
    expect(provider.displayName, 'Qwen3.6 Flash');
    expect(provider.model, 'qwen3.6-flash-2026-04-16');
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

  test('provider can override model name without changing defaults', () {
    final provider = ModelProviders.aliyunBailianQwenFlash.copyWith(
      model: 'qwen3.6-flash',
    );

    expect(provider.model, 'qwen3.6-flash');
    expect(provider.id, ModelProviders.aliyunBailianQwenFlash.id);
    expect(provider.defaultParameters['enable_thinking'], isFalse);
  });

  test('chat client has a finite request timeout', () {
    final client = OpenAiCompatibleChatClient();

    expect(client.requestTimeout, const Duration(seconds: 30));
  });
}
