import 'dart:io' show Platform;

class AmapRuntimeConfig {
  const AmapRuntimeConfig({
    this.androidKey = const String.fromEnvironment('AMAP_ANDROID_KEY'),
    this.iosKey = const String.fromEnvironment('AMAP_IOS_KEY'),
  });

  final String androidKey;
  final String iosKey;

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
