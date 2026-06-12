import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/models/model_api_key_store.dart';
import 'package:phone_agent/data/models/model_settings_store.dart';
import 'package:phone_agent/data/models/openai_compatible_chat_client.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';
import 'package:phone_agent/features/settings/model_settings_page.dart';

void main() {
  testWidgets('switching provider keeps model dropdown value valid', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ModelSettingsPage(
          apiKeyStore: _FakeApiKeyStore('test-key'),
          modelSettingsStore: InMemoryModelSettingsStore(),
          chatClient: _ImmediateConnectionClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('小米 MiMo'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('MiMo V2.5 Pro'), findsWidgets);
  });

  testWidgets(
    'connection test status uses selected model and deterministic result',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final modelSettingsStore = InMemoryModelSettingsStore();
      await modelSettingsStore.saveSelectedProviderId(
        ModelProviders.aliyunBailianQwenFlash.id,
      );
      await modelSettingsStore.saveModelName(
        ModelProviders.aliyunBailianQwenFlash.id,
        'qwen3.7-max-preview',
      );
      final chatClient = _DelayedConnectionClient();

      await tester.pumpWidget(
        MaterialApp(
          home: ModelSettingsPage(
            apiKeyStore: _FakeApiKeyStore('test-key'),
            modelSettingsStore: modelSettingsStore,
            chatClient: chatClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, '连接测试'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '连接测试'));
      await tester.pump();

      expect(
        find.textContaining('正在测试 阿里云百炼 / qwen3.7-max-preview'),
        findsOneWidget,
      );
      expect(chatClient.testedProvider!.model, 'qwen3.7-max-preview');

      chatClient.complete(
        const ModelConnectionResult(
          ok: true,
          message: '连接成功：阿里云百炼 / qwen3.7-max-preview 返回了有效响应。',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('连接成功：阿里云百炼 / qwen3.7-max-preview'),
        findsOneWidget,
      );
      expect(find.textContaining('抱歉'), findsNothing);
    },
  );
}

class _FakeApiKeyStore extends ModelApiKeyStore {
  _FakeApiKeyStore(this.apiKey);

  final String? apiKey;

  @override
  Future<String?> readApiKey(String providerId) async => apiKey;
}

class _DelayedConnectionClient extends OpenAiCompatibleChatClient {
  final _completer = Completer<ModelConnectionResult>();
  ModelProviderConfig? testedProvider;

  @override
  Future<ModelConnectionResult> testConnection({
    required ModelProviderConfig provider,
    required String apiKey,
  }) {
    testedProvider = provider;
    return _completer.future;
  }

  void complete(ModelConnectionResult result) {
    _completer.complete(result);
  }
}

class _ImmediateConnectionClient extends OpenAiCompatibleChatClient {
  @override
  Future<ModelConnectionResult> testConnection({
    required ModelProviderConfig provider,
    required String apiKey,
  }) async {
    return ModelConnectionResult(
      ok: true,
      message: '连接成功：${provider.vendorName} / ${provider.model}',
    );
  }
}
