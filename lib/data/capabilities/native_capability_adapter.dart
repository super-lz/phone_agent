import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui' as ui;

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:bz_location/bz_location.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as contacts;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as scanner;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/permissions/app_permission.dart';
import '../amap/amap_runtime_config.dart';
import '../permissions/app_permission_service.dart';

class NativeCapabilityAdapter {
  NativeCapabilityAdapter({
    DeviceInfoPlugin? deviceInfo,
    ImagePicker? imagePicker,
    AudioRecorder? audioRecorder,
    FlutterLocalNotificationsPlugin? notifications,
    AppPermissionService? permissionService,
    MethodChannel? nativeChannel,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _imagePicker = imagePicker ?? ImagePicker(),
       _audioRecorder = audioRecorder,
       _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _permissionService = permissionService ?? const AppPermissionService(),
       _nativeChannel =
           nativeChannel ??
           const MethodChannel('phone_agent/native_capabilities');

  final DeviceInfoPlugin _deviceInfo;
  final ImagePicker _imagePicker;
  AudioRecorder? _audioRecorder;
  final FlutterLocalNotificationsPlugin _notifications;
  final AppPermissionService _permissionService;
  final MethodChannel _nativeChannel;
  Future<bool>? _notificationInitialization;
  String? _activeAudioRecordingPath;
  String _screenOrientationMode = 'unlocked';
  String _systemUiMode = 'normal';
  List<SystemUiOverlay> _systemUiOverlays = SystemUiOverlay.values;

  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();

  Future<Map<String, Object?>> getDeviceInfo() async {
    try {
      final data = await _readPlatformDeviceData();
      final device = _normalizedDeviceInfo(data);
      return {
        'ok': true,
        'summary': _deviceSummary(device),
        'device': device,
        'rawDevice': data,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.device_info.failed', error, stackTrace);
      return {
        'ok': false,
        'error': error.toString(),
        'userMessage': '读取设备信息失败：$error',
      };
    }
  }

  Future<Map<String, Object?>> getAppInfo() async {
    try {
      final output = await _invokeNativeCapability('getAppInfo');
      final appName = _stringFromObject(output['appName']) ?? 'Phone Agent';
      final version = _stringFromObject(output['version']) ?? '';
      final buildNumber = _stringFromObject(output['buildNumber']) ?? '';
      final versionText = [
        if (version.isNotEmpty) version,
        if (buildNumber.isNotEmpty) 'build $buildNumber',
      ].join(' ');
      return {
        'ok': output['ok'] != false,
        'appName': appName,
        'version': version,
        'buildNumber': buildNumber,
        'summary': versionText.isEmpty
            ? '当前应用：$appName。'
            : '当前应用：$appName $versionText。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.app_info.failed', error, stackTrace);
      return _nativeCapabilityError(error, fallbackCode: 'app_info_failed');
    }
  }

  Future<Map<String, Object?>> _readPlatformDeviceData() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return _jsonSafeMap(info.data);
    }
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return _jsonSafeMap(info.data);
    }
    final info = await _deviceInfo.deviceInfo;
    return _jsonSafeMap(info.data);
  }

  Future<Map<String, Object?>> getCurrentTime() async {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    return {
      'ok': true,
      'summary': '设备当前本地时间：${now.toIso8601String()}（${now.timeZoneName}）。',
      'localIso': now.toIso8601String(),
      'utcIso': now.toUtc().toIso8601String(),
      'epochMilliseconds': now.millisecondsSinceEpoch,
      'timeZoneName': now.timeZoneName,
      'timeZoneOffsetMinutes': offset.inMinutes,
      'weekday': now.weekday,
    };
  }

  Future<Map<String, Object?>> readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      return {'ok': true, 'hasText': text.isNotEmpty, 'text': text};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.clipboard_read.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getBatteryStatus() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      final saveMode = await battery.isInBatterySaveMode;
      final stateLabel = _batteryStateLabel(state);
      return {
        'ok': true,
        'summary': '当前电量 $level%，$stateLabel${saveMode ? '，省电模式开启' : ''}。',
        'level': level,
        'state': stateLabel,
        'rawState': state.name,
        'isCharging': state == BatteryState.charging,
        'isFull': state == BatteryState.full,
        'isInBatterySaveMode': saveMode,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.battery_status.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getNetworkStatus() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final types = results.map((result) => result.name).toList();
      final connected =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      final typeText = types.isEmpty ? '未知' : types.join('、');
      return {
        'ok': true,
        'summary': connected ? '当前设备网络连接类型：$typeText。' : '当前设备未检测到网络连接。',
        'connected': connected,
        'types': types,
        'hasWifi': results.contains(ConnectivityResult.wifi),
        'hasMobile': results.contains(ConnectivityResult.mobile),
        'hasEthernet': results.contains(ConnectivityResult.ethernet),
        'hasVpn': results.contains(ConnectivityResult.vpn),
        'isMeteredLikely': results.contains(ConnectivityResult.mobile),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.network_status.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> writeClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return {'ok': true, 'length': text.length};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.clipboard_write.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> capturePhoto({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.camera,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _xFileOutput(file, mediaType: 'image', source: 'camera');
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.camera_capture_photo.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> captureVideo({Duration? maxDuration}) async {
    try {
      final permission = await _ensurePermissionsGranted(const [
        AppPermissionId.camera,
        AppPermissionId.microphone,
      ]);
      if (permission != null) {
        return _permissionErrorOutput(permission);
      }
      final file = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: maxDuration,
      );
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _xFileOutput(file, mediaType: 'video', source: 'camera');
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.camera_capture_video.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> setFlashlight(bool enabled) async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.camera,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }
      final output = await _invokeNativeCapability('setFlashlight', {
        'enabled': enabled,
      });
      final isEnabled = output['enabled'] == true;
      return {
        'ok': output['ok'] != false,
        'enabled': isEnabled,
        'available': output['available'] ?? true,
        'summary': isEnabled ? '手电筒已打开。' : '手电筒已关闭。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.flashlight_set.failed', error, stackTrace);
      return _nativeCapabilityError(error, fallbackCode: 'flashlight_failed');
    }
  }

  Future<Map<String, Object?>> getFlashlightStatus() async {
    try {
      final output = await _invokeNativeCapability('getFlashlightStatus');
      final isEnabled = output['enabled'] == true;
      return {
        'ok': output['ok'] != false,
        'enabled': isEnabled,
        'available': output['available'] ?? true,
        'summary': isEnabled ? '手电筒当前已打开。' : '手电筒当前已关闭。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.flashlight_status.failed', error, stackTrace);
      return _nativeCapabilityError(error, fallbackCode: 'flashlight_failed');
    }
  }

  Future<Map<String, Object?>> pickImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _xFileOutput(
        file,
        mediaType: 'image',
        source: 'photo_library',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.media_pick_image.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> pickImages({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
      if (files.isEmpty) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      final items = <Map<String, Object?>>[];
      for (final file in files) {
        final output = await _xFileOutput(
          file,
          mediaType: 'image',
          source: 'photo_library',
        );
        final item = Map<String, Object?>.from(output)..remove('ok');
        items.add(item);
      }
      return {
        'ok': true,
        'source': 'photo_library',
        'mediaType': 'image',
        'count': items.length,
        'items': items,
        'summary': '已选择 ${items.length} 张图片。',
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.media_pick_images.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> pickVideo() async {
    try {
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _xFileOutput(
        file,
        mediaType: 'video',
        source: 'photo_library',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.media_pick_video.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> pickSystemFile({
    List<String> allowedExtensions = const [],
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      final file = result.files.single;
      return _platformFileOutput(file);
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.file_pick_system_file.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> startAudioRecording() async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.microphone,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }
      if (await _recorder.isRecording()) {
        return const {'ok': false, 'error': 'recording_in_progress'};
      }
      final directory = await getTemporaryDirectory();
      final now = DateTime.now();
      final path =
          '${directory.path}/phone_agent_audio_${now.microsecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      _activeAudioRecordingPath = path;
      return {
        'ok': true,
        'recording': true,
        'source': 'microphone',
        'mediaType': 'audio',
        'name': _fileNameForPath(path),
        'path': path,
        'uri': Uri.file(path).toString(),
        'mimeType': 'audio/mp4',
        'extension': 'm4a',
        'startedAt': now.toIso8601String(),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.audio_record_start.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> stopAudioRecording() async {
    try {
      if (!await _recorder.isRecording()) {
        return const {'ok': false, 'error': 'no_active_recording'};
      }
      final path = await _recorder.stop();
      _activeAudioRecordingPath = null;
      if (path == null || path.trim().isEmpty) {
        return const {'ok': false, 'error': 'recording_file_unavailable'};
      }
      return await _localFileOutput(
        path,
        mediaType: 'audio',
        source: 'microphone',
        mimeType: 'audio/mp4',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.audio_record_stop.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> cancelAudioRecording() async {
    try {
      final wasRecording = await _recorder.isRecording();
      final path = _activeAudioRecordingPath;
      if (!wasRecording) {
        return const {'ok': false, 'error': 'no_active_recording'};
      }
      await _recorder.cancel();
      _activeAudioRecordingPath = null;
      return {'ok': true, 'cancelled': true, 'recording': false, 'path': path};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.audio_record_cancel.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> pickContact() async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.contacts,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }
      final contact = await contacts.FlutterContacts.native.showPicker(
        properties: const {
          contacts.ContactProperty.name,
          contacts.ContactProperty.phone,
          contacts.ContactProperty.email,
        },
      );
      if (contact == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return _contactOutput(contact);
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.contacts_pick.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> scanBarcodeFromCamera({
    List<String> formats = const [],
  }) async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.camera,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }
      final file = await _imagePicker.pickImage(source: ImageSource.camera);
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _scanBarcodeImage(
        file.path,
        source: 'camera',
        formats: formats,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.barcode_scan_camera.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> scanBarcodeFromImage({
    List<String> formats = const [],
  }) async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return const {'ok': false, 'error': 'user_cancelled'};
      }
      return await _scanBarcodeImage(
        file.path,
        source: 'photo_library',
        formats: formats,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.barcode_scan_image.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> shareText({
    required String text,
    String? subject,
  }) async {
    try {
      final result = await Share.share(text, subject: subject);
      return {
        'ok': true,
        'status': result.status.name,
        'rawStatus': result.raw,
        'length': text.length,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.share_text.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> hapticFeedback(String type) async {
    try {
      if (type == 'selection') {
        await HapticFeedback.selectionClick();
      } else if (type == 'medium') {
        await HapticFeedback.mediumImpact();
      } else if (type == 'heavy') {
        await HapticFeedback.heavyImpact();
      } else if (type == 'vibrate') {
        await HapticFeedback.vibrate();
      } else {
        await HapticFeedback.lightImpact();
      }
      return {'ok': true, 'type': type};
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.system_haptic_feedback.failed',
        error,
        stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> playSystemSound(String type) async {
    try {
      final soundType = type == 'click'
          ? SystemSoundType.click
          : SystemSoundType.alert;
      await SystemSound.play(soundType);
      return {'ok': true, 'type': soundType.name};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.system_sound_alert.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> setMediaVolume(double level) async {
    try {
      final output = await _invokeNativeCapability('setMediaVolume', {
        'level': level,
      });
      final currentLevel = _doubleFromObject(output['level']) ?? level;
      final canSet = output['canSet'] != false;
      return {
        'ok': output['ok'] != false,
        'level': currentLevel,
        'stream': output['stream'] ?? 'media',
        'canSet': canSet,
        'summary': canSet
            ? '媒体音量已设置为 ${(currentLevel * 100).round()}%。'
            : '当前平台不支持静默设置媒体音量。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.system_volume_set.failed', error, stackTrace);
      return _nativeCapabilityError(error, fallbackCode: 'volume_failed');
    }
  }

  Future<Map<String, Object?>> getMediaVolume() async {
    try {
      final output = await _invokeNativeCapability('getMediaVolume');
      final currentLevel = _doubleFromObject(output['level']);
      return {
        'ok': output['ok'] != false,
        'level': ?currentLevel,
        'stream': output['stream'] ?? 'media',
        'canSet': output['canSet'] == true,
        'summary': currentLevel == null
            ? '当前媒体音量不可用。'
            : '当前媒体音量约为 ${(currentLevel * 100).round()}%。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.system_volume_status.failed', error, stackTrace);
      return _nativeCapabilityError(error, fallbackCode: 'volume_failed');
    }
  }

  Future<Map<String, Object?>> openPermissionSettings() async {
    try {
      final opened = await _permissionService.openSettings();
      return {'ok': opened, 'opened': opened};
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.permission_open_settings.failed',
        error,
        stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> openExternalUrl(Uri uri) async {
    try {
      if (!_isAllowedExternalUri(uri)) {
        return {
          'ok': false,
          'error': 'unsupported_url_scheme',
          'scheme': uri.scheme,
        };
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return {
        'ok': opened,
        'opened': opened,
        'url': uri.toString(),
        'scheme': uri.scheme,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.url_open_external.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> setKeepScreenAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
      final current = await WakelockPlus.enabled;
      return {'ok': true, 'enabled': current};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.screen_keep_awake.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getKeepScreenAwake() async {
    try {
      final enabled = await WakelockPlus.enabled;
      return {'ok': true, 'enabled': enabled};
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.screen_keep_awake_status.failed',
        error,
        stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> setScreenBrightness(double level) async {
    try {
      final output = await _invokeNativeCapability('setScreenBrightness', {
        'level': level,
      });
      final currentLevel = _doubleFromObject(output['level']) ?? level;
      return {
        'ok': output['ok'] != false,
        'level': currentLevel,
        'usesSystemDefault': output['usesSystemDefault'] == true,
        'summary': '屏幕亮度已设置为 ${(currentLevel * 100).round()}%。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.screen_brightness_set.failed', error, stackTrace);
      return _nativeCapabilityError(
        error,
        fallbackCode: 'screen_brightness_failed',
      );
    }
  }

  Future<Map<String, Object?>> getScreenBrightness() async {
    try {
      final output = await _invokeNativeCapability('getScreenBrightness');
      final currentLevel = _doubleFromObject(output['level']);
      return {
        'ok': output['ok'] != false,
        'level': ?currentLevel,
        'usesSystemDefault': output['usesSystemDefault'] == true,
        'summary': currentLevel == null
            ? '当前屏幕亮度不可用。'
            : '当前屏幕亮度约为 ${(currentLevel * 100).round()}%。',
        ...output,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.screen_brightness_status.failed',
        error,
        stackTrace,
      );
      return _nativeCapabilityError(
        error,
        fallbackCode: 'screen_brightness_failed',
      );
    }
  }

  Future<Map<String, Object?>> getScreenMetrics() async {
    try {
      final dispatcher = ui.PlatformDispatcher.instance;
      final view = dispatcher.views.isEmpty ? null : dispatcher.views.first;
      final devicePixelRatio = view?.devicePixelRatio ?? 1.0;
      final physicalSize = view?.physicalSize ?? ui.Size.zero;
      final logicalWidth = devicePixelRatio == 0
          ? physicalSize.width
          : physicalSize.width / devicePixelRatio;
      final logicalHeight = devicePixelRatio == 0
          ? physicalSize.height
          : physicalSize.height / devicePixelRatio;
      final orientation = logicalWidth >= logicalHeight
          ? 'landscape'
          : 'portrait';
      return {
        'ok': true,
        'summary':
            '当前屏幕逻辑尺寸约为 ${logicalWidth.round()} x ${logicalHeight.round()}，像素比 ${devicePixelRatio.toStringAsFixed(2)}。',
        'viewId': view?.viewId,
        'physicalWidth': physicalSize.width,
        'physicalHeight': physicalSize.height,
        'logicalWidth': logicalWidth,
        'logicalHeight': logicalHeight,
        'devicePixelRatio': devicePixelRatio,
        'orientation': orientation,
        'platformBrightness': dispatcher.platformBrightness.name,
        'textScaleFactor': dispatcher.textScaleFactor,
        'locale': dispatcher.locale.toLanguageTag(),
        'locales': dispatcher.locales
            .map((locale) => locale.toLanguageTag())
            .toList(growable: false),
        'accessibility': _accessibilityFeaturesOutput(
          dispatcher.accessibilityFeatures,
        ),
        'padding': ?_viewPaddingOutput(view?.padding, devicePixelRatio),
        'viewPadding': ?_viewPaddingOutput(view?.viewPadding, devicePixelRatio),
        'viewInsets': ?_viewPaddingOutput(view?.viewInsets, devicePixelRatio),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.screen_metrics.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> setScreenOrientation(String mode) async {
    try {
      final normalized = _normalizeScreenOrientationMode(mode);
      final orientations = _screenOrientationsForMode(normalized);
      if (orientations == null) {
        return {
          'ok': false,
          'error': 'invalid_orientation_mode',
          'mode': mode,
          'allowedModes': _allowedScreenOrientationModes,
        };
      }
      await SystemChrome.setPreferredOrientations(orientations);
      _screenOrientationMode = normalized;
      return _screenOrientationStatusOutput();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.screen_orientation_set.failed',
        error,
        stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getScreenOrientation() async {
    return _screenOrientationStatusOutput();
  }

  Future<Map<String, Object?>> setSystemUiMode(String mode) async {
    try {
      final normalized = _normalizeSystemUiMode(mode);
      final configuration = _systemUiConfigurationForMode(normalized);
      if (configuration == null) {
        return {
          'ok': false,
          'error': 'invalid_system_ui_mode',
          'mode': mode,
          'allowedModes': _allowedSystemUiModes,
        };
      }

      await SystemChrome.setEnabledSystemUIMode(
        configuration.mode,
        overlays: configuration.overlays,
      );
      _systemUiMode = normalized;
      _systemUiOverlays = configuration.overlays;
      return _systemUiStatusOutput();
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.system_ui_set.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getSystemUiMode() async {
    return _systemUiStatusOutput();
  }

  Future<Map<String, Object?>> readAccelerometer() async {
    return _readSensor(
      name: 'accelerometer',
      stream: accelerometerEventStream(),
      values: (event) => {'x': event.x, 'y': event.y, 'z': event.z},
    );
  }

  Future<Map<String, Object?>> readGyroscope() async {
    return _readSensor(
      name: 'gyroscope',
      stream: gyroscopeEventStream(),
      values: (event) => {'x': event.x, 'y': event.y, 'z': event.z},
    );
  }

  Future<Map<String, Object?>> readMagnetometer() async {
    return _readSensor(
      name: 'magnetometer',
      stream: magnetometerEventStream(),
      values: (event) => {'x': event.x, 'y': event.y, 'z': event.z},
    );
  }

  Future<Map<String, Object?>> _readSensor<T>({
    required String name,
    required Stream<T> stream,
    required Map<String, Object?> Function(T event) values,
  }) async {
    try {
      final event = await stream.first.timeout(const Duration(seconds: 3));
      return {'ok': true, 'sensor': name, ...values(event)};
    } on TimeoutException {
      return {
        'ok': false,
        'sensor': name,
        'error': 'sensor_timeout',
        'detail': 'No $name event was emitted within the timeout.',
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.sensor_$name.failed', error, stackTrace);
      return {'ok': false, 'sensor': name, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getCurrentLocation() async {
    try {
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.location,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(
          permission,
          serviceDisabledError: 'location_service_disabled',
        );
      }

      final config = await AmapRuntimeConfig.load();

      if (!config.supportsCurrentPlatform) {
        return {
          'ok': false,
          'error': 'amap_platform_unsupported',
          'platform': config.platformName,
          'userMessage': '当前平台暂不支持高德定位：${config.platformName}。',
        };
      }
      if (!config.hasCurrentPlatformKey) {
        return {
          'ok': false,
          'error': 'amap_key_required',
          'platform': config.platformName,
          'userMessage':
              '缺少高德 ${config.platformName} Key。请在 config/amap_keys.json 中配置，或通过 --dart-define-from-file=config/amap_keys.local.json 启动应用。',
        };
      }
      return await _getCurrentAmapLocation(config);
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.warning('native.location_get_current.timeout', {
        'error': error.toString(),
      });
      AppLogger.error('native.location_get_current.failed', error, stackTrace);
      return {
        'ok': false,
        'error': 'location_timeout',
        'detail': error.toString(),
        'provider': 'amap_location',
        'userMessage':
            '已允许位置权限，但高德定位在限定时间内没有返回定位结果。请检查系统定位开关、高德 Key 包名/SHA1 配置和网络状态。',
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.location_get_current.failed', error, stackTrace);
      return {
        'ok': false,
        'error': error.toString(),
        'userMessage': '获取当前位置失败：$error',
      };
    }
  }

  Future<Map<String, Object?>> _getCurrentAmapLocation(
    AmapRuntimeConfig config,
  ) async {
    final location = AMapFlutterLocation();
    StreamSubscription<Map<String, Object>>? subscription;
    try {
      AMapFlutterLocation.updatePrivacyShow(true, true);
      AMapFlutterLocation.updatePrivacyAgree(true);
      AMapFlutterLocation.setApiKey(config.androidKey, config.iosKey);
      location.setLocationOption(
        AMapLocationOption(
          onceLocation: true,
          needAddress: true,
          locationMode: AMapLocationMode.Hight_Accuracy,
        ),
      );

      late final Future<Map<String, Object>> firstLocation;
      final completer = Completer<Map<String, Object>>();
      subscription = location.onLocationChanged().listen(
        (event) {
          if (!completer.isCompleted) {
            completer.complete(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      );
      firstLocation = completer.future;
      location.startLocation();
      final result = await firstLocation.timeout(const Duration(seconds: 15));
      return _amapLocationOutput(result);
    } finally {
      location.stopLocation();
      await subscription?.cancel();
      location.destroy();
    }
  }

  Map<String, Object?> _amapLocationOutput(Map<String, Object?> result) {
    final errorCode = result['errorCode'];
    if (errorCode != null) {
      return {
        'ok': false,
        'error': 'amap_location_failed',
        'provider': 'amap_location',
        'errorCode': errorCode,
        'errorInfo': result['errorInfo'],
        'userMessage': '高德定位失败：${result['errorInfo'] ?? errorCode}',
      };
    }
    final latitude = _numValue(result['latitude']);
    final longitude = _numValue(result['longitude']);
    if (latitude == null || longitude == null) {
      return {
        'ok': false,
        'error': 'amap_location_missing_coordinate',
        'provider': 'amap_location',
        'raw': result,
        'userMessage': '高德定位没有返回有效经纬度。',
      };
    }
    final accuracy = _numValue(result['accuracy']);
    final coordinateText =
        '纬度 ${latitude.toStringAsFixed(6)}，经度 ${longitude.toStringAsFixed(6)}';
    final accuracyText = accuracy == null
        ? ''
        : '，精度约 ${accuracy.toStringAsFixed(0)} 米';
    final address = _trimmedString(result['address']);
    return {
      'ok': true,
      'summary': address == null
          ? '当前位置：$coordinateText$accuracyText。'
          : '当前位置：$address（$coordinateText$accuracyText）。',
      'provider': 'amap_location',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': _numValue(result['altitude']),
      'heading': _numValue(result['bearing']),
      'speed': _numValue(result['speed']),
      'isCurrent': true,
      'locationSource': 'amap_current',
      'coordinateSystem': 'gcj02',
      'providerHint': 'amap_location_${Platform.operatingSystem}',
      'mapsUrl': 'https://uri.amap.com/marker?position=$longitude,$latitude',
      'timestamp': _trimmedString(result['locationTime']),
      'address': address,
      'country': _trimmedString(result['country']),
      'province': _trimmedString(result['province']),
      'city': _trimmedString(result['city']),
      'district': _trimmedString(result['district']),
      'street': _trimmedString(result['street']),
      'streetNumber': _trimmedString(result['streetNumber']),
      'cityCode': _trimmedString(result['cityCode']),
      'adCode': _trimmedString(result['adCode']),
      'description': _trimmedString(result['description']),
      'locationType': result['locationType'],
    };
  }

  num? _numValue(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  String? _trimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<Map<String, Object?>> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    try {
      if (!scheduledAt.isAfter(DateTime.now())) {
        return const {
          'ok': false,
          'error': 'scheduled_at_in_past',
          'detail': 'scheduledAt must be in the future',
        };
      }

      final initialized = await _ensureNotificationsInitialized();
      if (!initialized) {
        return const {
          'ok': false,
          'error': 'notification_initialization_failed',
        };
      }
      final permission = await _permissionService.ensureGranted(
        AppPermissionId.notifications,
      );
      if (!permission.granted) {
        return _permissionErrorOutput(permission);
      }

      final id = DateTime.now().microsecondsSinceEpoch.remainder(1 << 31);
      await _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
        notificationDetails: _notificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'source': 'phone_agent'}),
      );

      return {
        'ok': true,
        'notificationId': id,
        'title': title,
        'body': body,
        'scheduledAt': scheduledAt.toIso8601String(),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.notification_schedule.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> listPendingNotifications() async {
    try {
      final initialized = await _ensureNotificationsInitialized();
      if (!initialized) {
        return const {
          'ok': false,
          'error': 'notification_initialization_failed',
        };
      }
      final requests = await _notifications.pendingNotificationRequests();
      final notifications = [
        for (final request in requests)
          {
            'id': request.id,
            'title': request.title,
            'body': request.body,
            'payload': request.payload,
          },
      ];
      return {
        'ok': true,
        'count': notifications.length,
        'notifications': notifications,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.notification_pending.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> cancelNotification(int notificationId) async {
    try {
      final initialized = await _ensureNotificationsInitialized();
      if (!initialized) {
        return const {
          'ok': false,
          'error': 'notification_initialization_failed',
        };
      }
      await _notifications.cancel(id: notificationId);
      return {'ok': true, 'notificationId': notificationId, 'cancelled': true};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.notification_cancel.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> cancelAllNotifications() async {
    try {
      final initialized = await _ensureNotificationsInitialized();
      if (!initialized) {
        return const {
          'ok': false,
          'error': 'notification_initialization_failed',
        };
      }
      await _notifications.cancelAll();
      return const {'ok': true, 'cancelledAll': true};
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'native.notification_cancel_all.failed',
        error,
        stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> createCalendarEvent({
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool allDay = false,
  }) async {
    try {
      if (!endsAt.isAfter(startsAt)) {
        return const {
          'ok': false,
          'error': 'invalid_time_range',
          'detail': 'endsAt must be after startsAt',
        };
      }

      var completionInferred = false;
      final created =
          await Add2Calendar.addEvent2Cal(
            Event(
              title: title,
              description: description,
              location: location,
              startDate: startsAt,
              endDate: endsAt,
              allDay: allDay,
            ),
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              completionInferred = true;
              AppLogger.warning(
                'native.calendar_event_create.timeout_assumed_open',
              );
              return true;
            },
          );

      return {
        'ok': created,
        'title': title,
        'description': description,
        'location': location,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'allDay': allDay,
        'requiresUserConfirmation': true,
        'completionInferred': completionInferred,
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.calendar_event_create.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Map<String, Object?> _jsonSafeMap(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    return {'raw': decoded.toString()};
  }

  Future<Map<String, Object?>> _invokeNativeCapability(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final raw = await _nativeChannel.invokeMethod<Object?>(method, arguments);
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return {'ok': false, 'error': 'invalid_native_result'};
  }

  Map<String, Object?> _nativeCapabilityError(
    Object error, {
    required String fallbackCode,
  }) {
    if (error is PlatformException) {
      return {
        'ok': false,
        'error': error.code,
        'detail': error.message ?? error.details?.toString(),
        'userMessage': error.message ?? '手机原生能力调用失败。',
      };
    }
    return {
      'ok': false,
      'error': fallbackCode,
      'detail': error.toString(),
      'userMessage': '手机原生能力调用失败：$error',
    };
  }

  double? _doubleFromObject(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  String? _stringFromObject(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Map<String, Object?>? _viewPaddingOutput(
    ui.ViewPadding? padding,
    double devicePixelRatio,
  ) {
    if (padding == null) {
      return null;
    }
    final ratio = devicePixelRatio == 0 ? 1.0 : devicePixelRatio;
    return {
      'physical': {
        'left': padding.left,
        'top': padding.top,
        'right': padding.right,
        'bottom': padding.bottom,
      },
      'logical': {
        'left': padding.left / ratio,
        'top': padding.top / ratio,
        'right': padding.right / ratio,
        'bottom': padding.bottom / ratio,
      },
    };
  }

  Map<String, Object?> _accessibilityFeaturesOutput(
    ui.AccessibilityFeatures features,
  ) {
    return {
      'accessibleNavigation': features.accessibleNavigation,
      'invertColors': features.invertColors,
      'disableAnimations': features.disableAnimations,
      'boldText': features.boldText,
      'reduceMotion': features.reduceMotion,
      'highContrast': features.highContrast,
      'onOffSwitchLabels': features.onOffSwitchLabels,
      'supportsAnnounce': features.supportsAnnounce,
    };
  }

  Map<String, Object?> _normalizedDeviceInfo(Map<String, Object?> data) {
    if (Platform.isAndroid) {
      final version = _objectMap(data['version']);
      return {
        'platform': 'android',
        'manufacturer': data['manufacturer'],
        'brand': data['brand'],
        'model': data['model'],
        'device': data['device'],
        'product': data['product'],
        'hardware': data['hardware'],
        'board': data['board'],
        'display': data['display'],
        'fingerprint': data['fingerprint'],
        'host': data['host'],
        'osVersion': version['release'] ?? data['version.release'],
        'sdkInt': version['sdkInt'] ?? data['version.sdkInt'],
        'securityPatch': version['securityPatch'],
        'isPhysicalDevice': data['isPhysicalDevice'],
      };
    }
    if (Platform.isIOS) {
      final utsname = _objectMap(data['utsname']);
      return {
        'platform': 'ios',
        'name': data['name'],
        'model': data['model'],
        'localizedModel': data['localizedModel'],
        'systemName': data['systemName'],
        'osVersion': data['systemVersion'],
        'machine': utsname['machine'],
        'release': utsname['release'],
        'isPhysicalDevice': data['isPhysicalDevice'],
      };
    }
    return {'platform': Platform.operatingSystem, ...data};
  }

  Map<String, Object?> _objectMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  String _deviceSummary(Map<String, Object?> device) {
    final model = _stringValue(device['model']) ?? _stringValue(device['name']);
    final manufacturer = _stringValue(device['manufacturer']);
    final brand = _stringValue(device['brand']);
    final platform = _stringValue(device['platform']);
    final version = _stringValue(device['osVersion']);
    final physical = device['isPhysicalDevice'] == false ? '，可能是模拟器' : '';
    final maker = manufacturer == null || manufacturer == brand
        ? brand
        : '$manufacturer/$brand';
    final parts = <String>[?maker, ?model, ?platform, ?version];
    return parts.isEmpty
        ? '已读取设备信息$physical。'
        : '当前设备：${parts.join(' · ')}$physical。';
  }

  String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _batteryStateLabel(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return '充电中';
      case BatteryState.discharging:
        return '未充电';
      case BatteryState.full:
        return '已充满';
      case BatteryState.unknown:
        return '状态未知';
      case BatteryState.connectedNotCharging:
        return '已连接电源但未充电';
    }
  }

  Future<bool> _ensureNotificationsInitialized() {
    return _notificationInitialization ??= _initializeNotifications();
  }

  Future<bool> _initializeNotifications() async {
    tz_data.initializeTimeZones();
    final initialized = await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return initialized ?? true;
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'phone_agent_reminders',
        'Phone Agent Reminders',
        channelDescription: 'Scheduled notifications created by Phone Agent.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  Map<String, Object?> _permissionErrorOutput(
    AppPermissionSnapshot permission, {
    String? serviceDisabledError,
  }) {
    return {
      'ok': false,
      'error': _permissionErrorCode(
        permission.status,
        serviceDisabledError: serviceDisabledError,
      ),
      'detail': permission.detail,
      'permissionId': permission.descriptor.id.name,
      'permissionStatus': permission.status.name,
      'canOpenSettings': permission.canOpenSettings,
      'canRequestInApp': permission.canRequestInApp,
      'shouldOpenSettings': permission.shouldOpenSettings,
      'userMessage': _permissionUserMessage(permission),
    };
  }

  String _permissionUserMessage(AppPermissionSnapshot permission) {
    final title = permission.descriptor.title;
    if (permission.canRequestInApp) {
      return '$title权限尚未允许，已尝试发起系统授权申请；如果没有看到系统弹窗，请检查系统权限设置。';
    }
    if (permission.shouldOpenSettings) {
      return '$title权限或系统服务当前不可直接在 App 内恢复：${permission.detail}';
    }
    return '$title权限不可用：${permission.detail}';
  }

  String _permissionErrorCode(
    AppPermissionStatusKind status, {
    String? serviceDisabledError,
  }) {
    switch (status) {
      case AppPermissionStatusKind.serviceDisabled:
        return serviceDisabledError ?? 'permission_service_disabled';
      case AppPermissionStatusKind.permanentlyDenied:
        return 'permission_denied_forever';
      case AppPermissionStatusKind.restricted:
        return 'permission_restricted';
      case AppPermissionStatusKind.unavailable:
        return 'permission_unavailable';
      case AppPermissionStatusKind.granted:
      case AppPermissionStatusKind.limited:
      case AppPermissionStatusKind.provisional:
      case AppPermissionStatusKind.denied:
        return 'permission_denied';
    }
  }

  bool _isAllowedExternalUri(Uri uri) {
    return const {
      'http',
      'https',
      'mailto',
      'tel',
      'sms',
      'geo',
    }.contains(uri.scheme.toLowerCase());
  }

  Future<AppPermissionSnapshot?> _ensurePermissionsGranted(
    List<AppPermissionId> ids,
  ) async {
    for (final id in ids) {
      final permission = await _permissionService.ensureGranted(id);
      if (!permission.granted) {
        return permission;
      }
    }
    return null;
  }

  Future<Map<String, Object?>> _xFileOutput(
    XFile file, {
    required String mediaType,
    required String source,
  }) async {
    final path = file.path;
    final bytes = await file.length();
    final mimeType = file.mimeType ?? _mimeTypeForPath(path);
    final extension = _extensionForPath(path);
    return {
      'ok': true,
      'source': source,
      'mediaType': mediaType,
      'name': file.name,
      'path': path,
      'uri': Uri.file(path).toString(),
      'bytes': bytes,
      'mimeType': ?mimeType,
      'extension': ?extension,
    };
  }

  Future<Map<String, Object?>> _localFileOutput(
    String path, {
    required String mediaType,
    required String source,
    String? mimeType,
  }) async {
    final file = File(path);
    final bytes = await file.exists() ? await file.length() : null;
    final inferredMimeType = mimeType ?? _mimeTypeForPath(path);
    final extension = _extensionForPath(path);
    return {
      'ok': true,
      'source': source,
      'mediaType': mediaType,
      'name': _fileNameForPath(path),
      'path': path,
      'uri': Uri.file(path).toString(),
      'bytes': ?bytes,
      'mimeType': ?inferredMimeType,
      'extension': ?extension,
    };
  }

  Map<String, Object?> _platformFileOutput(PlatformFile file) {
    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      return {
        'ok': false,
        'error': 'file_path_unavailable',
        'name': file.name,
        'bytes': file.size,
      };
    }
    final mimeType = _mimeTypeForPath(path);
    final rawExtension = file.extension?.trim();
    final extension = rawExtension == null || rawExtension.isEmpty
        ? null
        : rawExtension;
    return {
      'ok': true,
      'source': 'system_file_picker',
      'mediaType': 'file',
      'name': file.name,
      'path': path,
      'uri': Uri.file(path).toString(),
      'bytes': file.size,
      'extension': ?extension,
      'mimeType': ?mimeType,
    };
  }

  Map<String, Object?> _contactOutput(contacts.Contact contact) {
    final phones = [
      for (final phone in contact.phones)
        {
          'number': phone.number,
          'normalizedNumber': phone.normalizedNumber,
          'isPrimary': phone.isPrimary,
          'label': phone.label.toJson(),
        },
    ];
    final emails = [
      for (final email in contact.emails)
        {
          'address': email.address,
          'isPrimary': email.isPrimary,
          'label': email.label.toJson(),
        },
    ];
    return {
      'ok': true,
      'source': 'native_contact_picker',
      'contactId': contact.id,
      'displayName': contact.displayName,
      'phones': phones,
      'emails': emails,
      'primaryPhone': phones.isEmpty ? null : phones.first['number'],
      'primaryEmail': emails.isEmpty ? null : emails.first['address'],
      'hasPhone': phones.isNotEmpty,
      'hasEmail': emails.isNotEmpty,
    };
  }

  Future<Map<String, Object?>> _scanBarcodeImage(
    String path, {
    required String source,
    List<String> formats = const [],
  }) async {
    final controller = scanner.MobileScannerController(autoStart: false);
    try {
      final requestedFormats = _barcodeFormatsFor(formats);
      final capture = await controller.analyzeImage(
        path,
        formats: requestedFormats,
      );
      final barcodes = capture?.barcodes ?? const <scanner.Barcode>[];
      if (barcodes.isEmpty) {
        return {
          'ok': false,
          'error': 'barcode_not_found',
          'source': source,
          'path': path,
          'uri': Uri.file(path).toString(),
        };
      }
      final normalized = [
        for (final barcode in barcodes) _barcodeOutput(barcode),
      ];
      final first = normalized.first;
      return {
        'ok': true,
        'source': source,
        'path': path,
        'uri': Uri.file(path).toString(),
        'count': normalized.length,
        'rawValue': first['rawValue'],
        'displayValue': first['displayValue'],
        'format': first['format'],
        'type': first['type'],
        'barcodes': normalized,
      };
    } finally {
      await controller.dispose();
    }
  }

  Map<String, Object?> _barcodeOutput(scanner.Barcode barcode) {
    return {
      'rawValue': barcode.rawValue,
      'displayValue': barcode.displayValue,
      'format': barcode.format.name,
      'type': barcode.type.name,
    };
  }

  List<scanner.BarcodeFormat> _barcodeFormatsFor(List<String> values) {
    final formats = values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .map(_barcodeFormatFor)
        .whereType<scanner.BarcodeFormat>()
        .toSet()
        .toList(growable: false);
    return formats;
  }

  scanner.BarcodeFormat? _barcodeFormatFor(String value) {
    switch (value) {
      case 'qr':
      case 'qr_code':
      case 'qrcode':
        return scanner.BarcodeFormat.qrCode;
      case 'ean13':
      case 'ean_13':
        return scanner.BarcodeFormat.ean13;
      case 'ean8':
      case 'ean_8':
        return scanner.BarcodeFormat.ean8;
      case 'code128':
      case 'code_128':
        return scanner.BarcodeFormat.code128;
      case 'code39':
      case 'code_39':
        return scanner.BarcodeFormat.code39;
      case 'code93':
      case 'code_93':
        return scanner.BarcodeFormat.code93;
      case 'data_matrix':
      case 'datamatrix':
        return scanner.BarcodeFormat.dataMatrix;
      case 'pdf417':
      case 'pdf_417':
        return scanner.BarcodeFormat.pdf417;
      case 'aztec':
        return scanner.BarcodeFormat.aztec;
      case 'upca':
      case 'upc_a':
        return scanner.BarcodeFormat.upcA;
      case 'upce':
      case 'upc_e':
        return scanner.BarcodeFormat.upcE;
      default:
        return null;
    }
  }

  static const List<String> _allowedScreenOrientationModes = [
    'unlocked',
    'portrait',
    'portrait_up',
    'portrait_down',
    'landscape',
    'landscape_left',
    'landscape_right',
  ];

  String _normalizeScreenOrientationMode(String mode) {
    final normalized = mode.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    switch (normalized) {
      case 'free':
      case 'system':
      case 'auto':
      case 'default':
      case 'unlock':
      case 'unlocked':
        return 'unlocked';
      case 'portraitup':
      case 'portrait_up':
        return 'portrait_up';
      case 'portraitdown':
      case 'portrait_down':
        return 'portrait_down';
      case 'landscapeleft':
      case 'landscape_left':
        return 'landscape_left';
      case 'landscaperight':
      case 'landscape_right':
        return 'landscape_right';
      default:
        return normalized;
    }
  }

  List<DeviceOrientation>? _screenOrientationsForMode(String mode) {
    switch (mode) {
      case 'unlocked':
        return const [];
      case 'portrait':
        return const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
      case 'portrait_up':
        return const [DeviceOrientation.portraitUp];
      case 'portrait_down':
        return const [DeviceOrientation.portraitDown];
      case 'landscape':
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case 'landscape_left':
        return const [DeviceOrientation.landscapeLeft];
      case 'landscape_right':
        return const [DeviceOrientation.landscapeRight];
      default:
        return null;
    }
  }

  Map<String, Object?> _screenOrientationStatusOutput() {
    final orientations =
        _screenOrientationsForMode(_screenOrientationMode) ?? const [];
    final labels = orientations
        .map(_deviceOrientationLabel)
        .toList(growable: false);
    final locked = _screenOrientationMode != 'unlocked';
    return {
      'ok': true,
      'mode': _screenOrientationMode,
      'locked': locked,
      'preferredOrientations': labels,
      'summary': locked
          ? '当前应用屏幕方向已锁定为${_screenOrientationModeLabel(_screenOrientationMode)}。'
          : '当前应用屏幕方向跟随系统自动旋转。',
    };
  }

  String _deviceOrientationLabel(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 'portrait_up';
      case DeviceOrientation.portraitDown:
        return 'portrait_down';
      case DeviceOrientation.landscapeLeft:
        return 'landscape_left';
      case DeviceOrientation.landscapeRight:
        return 'landscape_right';
    }
  }

  String _screenOrientationModeLabel(String mode) {
    switch (mode) {
      case 'portrait':
        return '竖屏';
      case 'portrait_up':
        return '正向竖屏';
      case 'portrait_down':
        return '倒置竖屏';
      case 'landscape':
        return '横屏';
      case 'landscape_left':
        return '左横屏';
      case 'landscape_right':
        return '右横屏';
      default:
        return mode;
    }
  }

  static const List<String> _allowedSystemUiModes = [
    'normal',
    'fullscreen',
    'edge_to_edge',
    'lean_back',
    'immersive',
    'immersive_sticky',
  ];

  String _normalizeSystemUiMode(String mode) {
    final normalized = mode.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    switch (normalized) {
      case 'default':
      case 'visible':
      case 'manual':
      case 'restore':
      case 'restored':
      case 'normal':
        return 'normal';
      case 'full_screen':
      case 'hide':
      case 'hidden':
      case 'fullscreen':
        return 'fullscreen';
      case 'edge':
      case 'edge_to_edge':
      case 'edgetoedge':
        return 'edge_to_edge';
      case 'leanback':
      case 'lean_back':
        return 'lean_back';
      case 'immersivesticky':
      case 'immersive_sticky':
        return 'immersive_sticky';
      default:
        return normalized;
    }
  }

  ({SystemUiMode mode, List<SystemUiOverlay> overlays})?
  _systemUiConfigurationForMode(String mode) {
    switch (mode) {
      case 'normal':
        return (mode: SystemUiMode.manual, overlays: SystemUiOverlay.values);
      case 'fullscreen':
        return (mode: SystemUiMode.manual, overlays: const []);
      case 'edge_to_edge':
        return (mode: SystemUiMode.edgeToEdge, overlays: const []);
      case 'lean_back':
        return (mode: SystemUiMode.leanBack, overlays: const []);
      case 'immersive':
        return (mode: SystemUiMode.immersive, overlays: const []);
      case 'immersive_sticky':
        return (mode: SystemUiMode.immersiveSticky, overlays: const []);
      default:
        return null;
    }
  }

  Map<String, Object?> _systemUiStatusOutput() {
    final overlays = _systemUiOverlays
        .map(_systemUiOverlayLabel)
        .toList(growable: false);
    return {
      'ok': true,
      'mode': _systemUiMode,
      'overlays': overlays,
      'isFullscreen': _systemUiMode != 'normal' && overlays.isEmpty,
      'summary': _systemUiMode == 'normal'
          ? '当前应用已恢复显示系统状态栏和导航栏。'
          : '当前应用系统 UI 已切换为${_systemUiModeLabel(_systemUiMode)}模式。',
    };
  }

  String _systemUiOverlayLabel(SystemUiOverlay overlay) {
    switch (overlay) {
      case SystemUiOverlay.top:
        return 'top';
      case SystemUiOverlay.bottom:
        return 'bottom';
    }
  }

  String _systemUiModeLabel(String mode) {
    switch (mode) {
      case 'fullscreen':
        return '全屏';
      case 'edge_to_edge':
        return '边到边';
      case 'lean_back':
        return '轻量沉浸';
      case 'immersive':
        return '沉浸';
      case 'immersive_sticky':
        return '粘性沉浸';
      case 'normal':
      default:
        return '正常显示';
    }
  }

  String? _extensionForPath(String path) {
    final normalized = path.split('?').first;
    final slash = normalized.lastIndexOf('/');
    final fileName = slash < 0 ? normalized : normalized.substring(slash + 1);
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return null;
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _fileNameForPath(String path) {
    final normalized = path.split('?').first;
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  String? _mimeTypeForPath(String path) {
    switch (_extensionForPath(path)) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return null;
    }
  }
}
