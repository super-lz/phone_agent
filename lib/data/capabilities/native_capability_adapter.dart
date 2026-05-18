import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/permissions/app_permission.dart';
import '../permissions/app_permission_service.dart';

class NativeCapabilityAdapter {
  NativeCapabilityAdapter({
    DeviceInfoPlugin? deviceInfo,
    FlutterLocalNotificationsPlugin? notifications,
    AppPermissionService? permissionService,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _permissionService = permissionService ?? const AppPermissionService();

  final DeviceInfoPlugin _deviceInfo;
  final FlutterLocalNotificationsPlugin _notifications;
  final AppPermissionService _permissionService;
  Future<bool>? _notificationInitialization;

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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _currentLocationSettings(),
      );
      final accuracy = position.accuracy;
      return {
        'ok': true,
        'summary':
            '当前位置：纬度 ${position.latitude.toStringAsFixed(6)}，经度 ${position.longitude.toStringAsFixed(6)}，精度约 ${accuracy.toStringAsFixed(0)} 米。',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': accuracy,
        'altitude': position.altitude,
        'heading': position.heading,
        'speed': position.speed,
        'isMocked': position.isMocked,
        'providerHint': Platform.isAndroid
            ? 'android_location_manager'
            : Platform.operatingSystem,
        'mapsUrl':
            'https://maps.google.com/?q=${position.latitude},${position.longitude}',
        'timestamp': position.timestamp.toIso8601String(),
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

  LocationSettings _currentLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
        forceLocationManager: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    );
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
}
