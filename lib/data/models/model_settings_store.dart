import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ModelSettingsStore {
  Future<String?> readSelectedProviderId();

  Future<void> saveSelectedProviderId(String providerId);

  Future<String?> readModelName(String providerId);

  Future<void> saveModelName(String providerId, String modelName);

  Future<void> deleteModelName(String providerId);
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

  static String _modelNameKey(String providerId) {
    return 'model_name_$providerId';
  }

  static const _selectedProviderKey = 'selected_model_provider_id';
}

class InMemoryModelSettingsStore implements ModelSettingsStore {
  final _modelNames = <String, String>{};
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
}
