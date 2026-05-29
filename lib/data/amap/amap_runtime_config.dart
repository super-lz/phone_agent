import 'dart:convert';
import 'dart:io' show File, Platform;

class AmapRuntimeConfig {
  const AmapRuntimeConfig({
    this.androidKey = const String.fromEnvironment('AMAP_ANDROID_KEY'),
    this.iosKey = const String.fromEnvironment('AMAP_IOS_KEY'),
  });

  final String androidKey;
  final String iosKey;

  static Future<AmapRuntimeConfig> load() async {
    const envAndroid = String.fromEnvironment('AMAP_ANDROID_KEY');
    const envIos = String.fromEnvironment('AMAP_IOS_KEY');
    
    if (envAndroid.isNotEmpty || envIos.isNotEmpty) {
      return const AmapRuntimeConfig(
        androidKey: envAndroid,
        iosKey: envIos,
      );
    }

    try {
      final localFile = File('config/amap_keys.local.json');
      final sharedFile = File('config/amap_keys.json');
      File? file;
      
      if (await localFile.exists()) {
        file = localFile;
      } else if (await sharedFile.exists()) {
        file = sharedFile;
      }

      if (file != null) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        if (json is Map<String, Object?>) {
          return AmapRuntimeConfig(
            androidKey: json['AMAP_ANDROID_KEY'] as String? ?? '',
            iosKey: json['AMAP_IOS_KEY'] as String? ?? '',
          );
        }
      }
    } catch (_) {
      // Fallback to defaults
    }

    return const AmapRuntimeConfig();
  }

  String get platformName {
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    return Platform.operatingSystem;
  }

  bool get supportsCurrentPlatform => Platform.isAndroid || Platform.isIOS;

  String get currentPlatformKey {
    if (Platform.isAndroid) {
      return androidKey.trim();
    }
    if (Platform.isIOS) {
      return iosKey.trim();
    }
    return '';
  }

  bool get hasCurrentPlatformKey => currentPlatformKey.isNotEmpty;
}
