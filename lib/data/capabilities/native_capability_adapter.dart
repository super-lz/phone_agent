import 'dart:async';
import 'dart:convert';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/logging/app_logger.dart';

class NativeCapabilityAdapter {
  NativeCapabilityAdapter({
    DeviceInfoPlugin? deviceInfo,
    FlutterLocalNotificationsPlugin? notifications,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final DeviceInfoPlugin _deviceInfo;
  final FlutterLocalNotificationsPlugin _notifications;
  Future<bool>? _notificationInitialization;

  Future<Map<String, Object?>> getDeviceInfo() async {
    try {
      final info = await _deviceInfo.deviceInfo;
      final data = _jsonSafeMap(info.data);
      return {'ok': true, 'device': data};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.device_info.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getCurrentTime() async {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    return {
      'ok': true,
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

  Future<Map<String, Object?>> writeClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return {'ok': true, 'length': text.length};
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.clipboard_write.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const {
          'ok': false,
          'error': 'location_service_disabled',
          'detail': 'location service is disabled',
        };
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const {
          'ok': false,
          'error': 'permission_denied',
          'detail': 'location permission denied',
        };
      }
      if (permission == LocationPermission.deniedForever) {
        return const {
          'ok': false,
          'error': 'permission_denied_forever',
          'detail': 'location permission denied forever',
        };
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return {
        'ok': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'heading': position.heading,
        'speed': position.speed,
        'timestamp': position.timestamp.toIso8601String(),
      };
    } on Object catch (error, stackTrace) {
      AppLogger.error('native.location_get_current.failed', error, stackTrace);
      return {'ok': false, 'error': error.toString()};
    }
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
      final permissionGranted = await _requestNotificationPermission();
      if (!permissionGranted) {
        return const {
          'ok': false,
          'error': 'permission_denied',
          'detail': 'notification permission denied',
        };
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

  Future<bool> _requestNotificationPermission() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    if (androidGranted == false) {
      return false;
    }

    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return iosGranted ?? true;
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
}
