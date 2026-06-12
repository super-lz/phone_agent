import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/models/model_settings_store.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';

void main() {
  test('aliyun bailian qwen flash uses openai-compatible defaults', () {
    final provider = ModelProviders.aliyunBailianQwenFlash;

    expect(provider.vendorName, '阿里云百炼');
    expect(provider.displayName, 'Qwen3.6 Flash');
    expect(provider.group, ModelProviderGroup.domestic);
    expect(provider.apiProtocol, ModelApiProtocol.openAiChatCompletions);
    expect(provider.defaultModel, 'qwen3.6-flash-2026-04-16');
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
    expect(provider.defaultModel, 'qwen3.6-flash-2026-04-16');
    expect(provider.defaultParameters['enable_thinking'], isFalse);
  });

  test('model option can expose model-level context window', () {
    final provider = ModelProviders.moonshotKimi.copyWith(
      model: 'moonshot-v1-128k',
    );

    expect(provider.effectiveMaxContextTokens, 131072);
    expect(provider.hasKnownContextWindow, isTrue);
  });

  test('manual context window override wins over built-in model option', () {
    final provider = ModelProviders.moonshotKimi.copyWith(
      model: 'moonshot-v1-8k',
      contextWindowOverrideTokens: 64000,
    );

    expect(provider.effectiveMaxContextTokens, 64000);
  });

  test('registry includes domestic international and aggregator providers', () {
    expect(
      ModelProviders.byGroup(ModelProviderGroup.domestic),
      contains(ModelProviders.miniMax),
    );
    expect(
      ModelProviders.byGroup(ModelProviderGroup.international),
      contains(ModelProviders.anthropicClaude),
    );
    expect(
      ModelProviders.byGroup(ModelProviderGroup.aggregator),
      contains(ModelProviders.openRouter),
    );
  });

  test(
    'minimax uses official openai-compatible endpoint and model presets',
    () {
      final provider = ModelProviders.miniMax;

      expect(
        provider.chatCompletionsEndpoint.toString(),
        'https://api.minimaxi.com/v1/chat/completions',
      );
      expect(provider.defaultModel, 'MiniMax-M3');
      expect(provider.supportsTools, isTrue);
      expect(
        provider.modelOptions.map((option) => option.name),
        contains('MiniMax-M2.7-highspeed'),
      );
    },
  );

  test('anthropic uses messages protocol and required version header', () {
    final provider = ModelProviders.anthropicClaude;

    expect(provider.apiProtocol, ModelApiProtocol.anthropicMessages);
    expect(
      provider.anthropicMessagesEndpoint.toString(),
      'https://api.anthropic.com/v1/messages',
    );
    expect(provider.defaultHeaders['anthropic-version'], '2023-06-01');
    expect(provider.supportsTools, isFalse);
  });

  test('mimo uses real openai-compatible api endpoint', () {
    final provider = ModelProviders.xiaomiMimo;

    expect(provider.apiProtocol, ModelApiProtocol.openAiChatCompletions);
    expect(provider.canRunConnectionTest, isTrue);
    expect(provider.requiresApiKey, isTrue);
    expect(provider.supportsTools, isTrue);
    expect(
      provider.chatCompletionsEndpoint.toString(),
      'https://api.xiaomimimo.com/v1/chat/completions',
    );
    expect(provider.effectiveMaxContextTokens, 1000000);
    expect(
      provider.modelOptions.map((option) => option.name),
      contains('mimo-v2.5-pro'),
    );
    expect(
      provider.modelOptions.map((option) => option.name),
      isNot(contains('mimo-v2.5-tts')),
    );
  });

  test(
    'model settings store saves model names independently per provider',
    () async {
      final store = InMemoryModelSettingsStore();

      await store.saveModelName(
        ModelProviders.deepSeek.id,
        'deepseek-v4-flash',
      );
      await store.saveModelName(ModelProviders.miniMax.id, 'MiniMax-M2');

      expect(
        await store.readModelName(ModelProviders.deepSeek.id),
        'deepseek-v4-flash',
      );
      expect(
        await store.readModelName(ModelProviders.miniMax.id),
        'MiniMax-M2',
      );
    },
  );

  test(
    'model settings store saves context windows independently per provider',
    () async {
      final store = InMemoryModelSettingsStore();

      await store.saveContextWindowTokens(ModelProviders.deepSeek.id, 64000);
      await store.saveContextWindowTokens(ModelProviders.miniMax.id, 128000);

      expect(
        await store.readContextWindowTokens(ModelProviders.deepSeek.id),
        64000,
      );
      expect(
        await store.readContextWindowTokens(ModelProviders.miniMax.id),
        128000,
      );

      await store.deleteContextWindowTokens(ModelProviders.deepSeek.id);

      expect(
        await store.readContextWindowTokens(ModelProviders.deepSeek.id),
        isNull,
      );
    },
  );

  test('chat client has a finite request timeout', () {
    final client = OpenAiCompatibleChatClient();

    expect(client.requestTimeout, const Duration(seconds: 30));
  });
}
