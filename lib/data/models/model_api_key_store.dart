import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ModelApiKeyStore {
  ModelApiKeyStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<String?> readApiKey(String providerId) {
    return _secureStorage.read(key: _key(providerId));
  }

  Future<void> saveApiKey(String providerId, String apiKey) {
    return _secureStorage.write(key: _key(providerId), value: apiKey);
  }

  Future<void> deleteApiKey(String providerId) {
    return _secureStorage.delete(key: _key(providerId));
  }

  static String _key(String providerId) {
    return 'model_api_key_$providerId';
  }
}
