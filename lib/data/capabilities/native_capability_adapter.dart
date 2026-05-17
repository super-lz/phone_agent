import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/logging/app_logger.dart';

class NativeCapabilityAdapter {
  NativeCapabilityAdapter({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

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

  Map<String, Object?> _jsonSafeMap(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    return {'raw': decoded.toString()};
  }
}
