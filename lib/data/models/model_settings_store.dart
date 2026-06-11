import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ModelSettingsStore {
  Future<String?> readSelectedProviderId();

  Future<void> saveSelectedProviderId(String providerId);

  Future<String?> readModelName(String providerId);

  Future<void> saveModelName(String providerId, String modelName);

  Future<void> deleteModelName(String providerId);

  Future<int?> readContextWindowTokens(String providerId);

  Future<void> saveContextWindowTokens(String providerId, int tokens);

  Future<void> deleteContextWindowTokens(String providerId);
}

class SecureModelSettingsStore implements ModelSettingsStore {
  SecureModelSettingsStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> readSelectedProviderId() {
    return _secureStorage.read(key: _selectedProviderKey);
  }

  @override
  Future<void> saveSelectedProviderId(String providerId) {
    return _secureStorage.write(key: _selectedProviderKey, value: providerId);
  }

  @override
  Future<String?> readModelName(String providerId) {
    return _secureStorage.read(key: _modelNameKey(providerId));
  }

  @override
  Future<void> saveModelName(String providerId, String modelName) {
    return _secureStorage.write(
      key: _modelNameKey(providerId),
      value: modelName,
    );
  }

  @override
  Future<void> deleteModelName(String providerId) {
    return _secureStorage.delete(key: _modelNameKey(providerId));
  }

  @override
  Future<int?> readContextWindowTokens(String providerId) async {
    final value = await _secureStorage.read(key: _contextWindowKey(providerId));
    if (value == null) {
      return null;
    }
    final parsed = int.tryParse(value);
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  @override
  Future<void> saveContextWindowTokens(String providerId, int tokens) {
    return _secureStorage.write(
      key: _contextWindowKey(providerId),
      value: tokens.toString(),
    );
  }

  @override
  Future<void> deleteContextWindowTokens(String providerId) {
    return _secureStorage.delete(key: _contextWindowKey(providerId));
  }

  static String _modelNameKey(String providerId) {
    return 'model_name_$providerId';
  }

  static String _contextWindowKey(String providerId) {
    return 'context_window_tokens_$providerId';
  }

  static const _selectedProviderKey = 'selected_model_provider_id';
}

class InMemoryModelSettingsStore implements ModelSettingsStore {
  final _modelNames = <String, String>{};
  final _contextWindowTokens = <String, int>{};
  String? _selectedProviderId;

  @override
  Future<String?> readSelectedProviderId() async {
    return _selectedProviderId;
  }

  @override
  Future<void> saveSelectedProviderId(String providerId) async {
    _selectedProviderId = providerId;
  }

  @override
  Future<String?> readModelName(String providerId) async {
    return _modelNames[providerId];
  }

  @override
  Future<void> saveModelName(String providerId, String modelName) async {
    _modelNames[providerId] = modelName;
  }

  @override
  Future<void> deleteModelName(String providerId) async {
    _modelNames.remove(providerId);
  }

  @override
  Future<int?> readContextWindowTokens(String providerId) async {
    return _contextWindowTokens[providerId];
  }

  @override
  Future<void> saveContextWindowTokens(String providerId, int tokens) async {
    _contextWindowTokens[providerId] = tokens;
  }

  @override
  Future<void> deleteContextWindowTokens(String providerId) async {
    _contextWindowTokens.remove(providerId);
  }
}
