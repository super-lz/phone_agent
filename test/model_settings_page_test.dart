import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/data/models/model_api_key_store.dart';
import 'package:phone_agent/data/models/model_settings_store.dart';
import 'package:phone_agent/domain/models/model_provider_config.dart';
import 'package:phone_agent/features/settings/model_settings_page.dart';

void main() {
  testWidgets('settings page switches provider and saves independent config', (
    tester,
  ) async {
    final apiKeyStore = _FakeApiKeyStore();
    final settingsStore = InMemoryModelSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: ModelSettingsPage(
          apiKeyStore: apiKeyStore,
          modelSettingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('MiniMax').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'minimax-key');
    await tester.ensureVisible(find.text('保存配置'));
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(
      await apiKeyStore.readApiKey(ModelProviders.miniMax.id),
      'minimax-key',
    );
    expect(
      await settingsStore.readModelName(ModelProviders.miniMax.id),
      'MiniMax-M3',
    );
    expect(
      await settingsStore.readSelectedProviderId(),
      ModelProviders.miniMax.id,
    );
  });

  testWidgets('settings page saves custom model per provider', (tester) async {
    final apiKeyStore = _FakeApiKeyStore();
    final settingsStore = InMemoryModelSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: ModelSettingsPage(
          apiKeyStore: apiKeyStore,
          modelSettingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('DeepSeek').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'deepseek-key');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义模型名称').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'deepseek-custom');
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(
      await apiKeyStore.readApiKey(ModelProviders.deepSeek.id),
      'deepseek-key',
    );
    expect(
      await settingsStore.readModelName(ModelProviders.deepSeek.id),
      'deepseek-custom',
    );
  });

  testWidgets('settings page saves manual context window per provider', (
    tester,
  ) async {
    final apiKeyStore = _FakeApiKeyStore();
    final settingsStore = InMemoryModelSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: ModelSettingsPage(
          apiKeyStore: apiKeyStore,
          modelSettingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('MiniMax').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'minimax-key');
    await tester.enterText(
      find.widgetWithText(TextField, '最大上下文 token（可选）'),
      '128000',
    );
    await tester.ensureVisible(find.text('保存配置'));
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(
      await settingsStore.readContextWindowTokens(ModelProviders.miniMax.id),
      128000,
    );
  });
}

class _FakeApiKeyStore extends ModelApiKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> readApiKey(String providerId) async {
    return values[providerId];
  }

  @override
  Future<void> saveApiKey(String providerId, String apiKey) async {
    values[providerId] = apiKey;
  }

  @override
  Future<void> deleteApiKey(String providerId) async {
    values.remove(providerId);
  }
}
