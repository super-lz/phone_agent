import '../../data/capabilities/native_capability_adapter.dart';
import 'capability_execution_result.dart';

class NativeCapabilityHandler {
  const NativeCapabilityHandler({required NativeCapabilityAdapter adapter})
    : _adapter = adapter;

  final NativeCapabilityAdapter _adapter;

  Future<CapabilityExecutionResult> deviceInfo() async {
    return CapabilityExecutionResult(
      capabilityId: 'device.info',
      output: await _adapter.getDeviceInfo(),
    );
  }

  Future<CapabilityExecutionResult> getCurrentTime() async {
    return CapabilityExecutionResult(
      capabilityId: 'time.get_current',
      output: await _adapter.getCurrentTime(),
    );
  }

  Future<CapabilityExecutionResult> readClipboard() async {
    return CapabilityExecutionResult(
      capabilityId: 'clipboard.read',
      output: await _adapter.readClipboard(),
    );
  }

  Future<CapabilityExecutionResult> getBatteryStatus() async {
    return CapabilityExecutionResult(
      capabilityId: 'battery.status',
      output: await _adapter.getBatteryStatus(),
    );
  }

  Future<CapabilityExecutionResult> getNetworkStatus() async {
    return CapabilityExecutionResult(
      capabilityId: 'network.status',
      output: await _adapter.getNetworkStatus(),
    );
  }

  Future<CapabilityExecutionResult> writeClipboard({
    required Map<String, Object?> arguments,
  }) async {
    final rawText = arguments['text'];
    if (rawText is! String) {
      return const CapabilityExecutionResult(
        capabilityId: 'clipboard.write',
        output: {'ok': false, 'error': 'text is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'clipboard.write',
      output: await _adapter.writeClipboard(rawText),
    );
  }

  Future<CapabilityExecutionResult> capturePhoto({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'camera.capture_photo',
      output: await _adapter.capturePhoto(
        maxWidth: _optionalPositiveDouble(arguments['max_width']),
        maxHeight: _optionalPositiveDouble(arguments['max_height']),
        imageQuality: _optionalImageQuality(arguments['image_quality']),
      ),
    );
  }

  Future<CapabilityExecutionResult> captureVideo({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'camera.capture_video',
      output: await _adapter.captureVideo(
        maxDuration: _optionalDuration(arguments['max_duration_seconds']),
      ),
    );
  }

  Future<CapabilityExecutionResult> setFlashlight({
    required Map<String, Object?> arguments,
  }) async {
    final rawEnabled = arguments['enabled'];
    if (rawEnabled is! bool) {
      return const CapabilityExecutionResult(
        capabilityId: 'flashlight.set',
        output: {'ok': false, 'error': 'enabled is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'flashlight.set',
      output: await _adapter.setFlashlight(rawEnabled),
    );
  }

  Future<CapabilityExecutionResult> getFlashlightStatus() async {
    return CapabilityExecutionResult(
      capabilityId: 'flashlight.status',
      output: await _adapter.getFlashlightStatus(),
    );
  }

  Future<CapabilityExecutionResult> pickImage({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'media.pick_image',
      output: await _adapter.pickImage(
        maxWidth: _optionalPositiveDouble(arguments['max_width']),
        maxHeight: _optionalPositiveDouble(arguments['max_height']),
        imageQuality: _optionalImageQuality(arguments['image_quality']),
      ),
    );
  }

  Future<CapabilityExecutionResult> pickImages({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'media.pick_images',
      output: await _adapter.pickImages(
        maxWidth: _optionalPositiveDouble(arguments['max_width']),
        maxHeight: _optionalPositiveDouble(arguments['max_height']),
        imageQuality: _optionalImageQuality(arguments['image_quality']),
      ),
    );
  }

  Future<CapabilityExecutionResult> pickVideo() async {
    return CapabilityExecutionResult(
      capabilityId: 'media.pick_video',
      output: await _adapter.pickVideo(),
    );
  }

  Future<CapabilityExecutionResult> pickSystemFile({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'file.pick_system_file',
      output: await _adapter.pickSystemFile(
        allowedExtensions: _stringList(arguments['allowed_extensions']),
      ),
    );
  }

  Future<CapabilityExecutionResult> startAudioRecording() async {
    return CapabilityExecutionResult(
      capabilityId: 'audio.record_start',
      output: await _adapter.startAudioRecording(),
    );
  }

  Future<CapabilityExecutionResult> stopAudioRecording() async {
    return CapabilityExecutionResult(
      capabilityId: 'audio.record_stop',
      output: await _adapter.stopAudioRecording(),
    );
  }

  Future<CapabilityExecutionResult> cancelAudioRecording() async {
    return CapabilityExecutionResult(
      capabilityId: 'audio.record_cancel',
      output: await _adapter.cancelAudioRecording(),
    );
  }

  Future<CapabilityExecutionResult> pickContact() async {
    return CapabilityExecutionResult(
      capabilityId: 'contacts.pick',
      output: await _adapter.pickContact(),
    );
  }

  Future<CapabilityExecutionResult> scanBarcodeFromCamera({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'barcode.scan_camera',
      output: await _adapter.scanBarcodeFromCamera(
        formats: _stringList(arguments['formats']),
      ),
    );
  }

  Future<CapabilityExecutionResult> scanBarcodeFromImage({
    required Map<String, Object?> arguments,
  }) async {
    return CapabilityExecutionResult(
      capabilityId: 'barcode.scan_image',
      output: await _adapter.scanBarcodeFromImage(
        formats: _stringList(arguments['formats']),
      ),
    );
  }

  Future<CapabilityExecutionResult> shareText({
    required Map<String, Object?> arguments,
  }) async {
    final rawText = arguments['text'];
    if (rawText is! String || rawText.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'share.text',
        output: {'ok': false, 'error': 'text is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'share.text',
      output: await _adapter.shareText(
        text: rawText.trim(),
        subject: _optionalTrimmedString(arguments['subject']),
      ),
    );
  }

  Future<CapabilityExecutionResult> hapticFeedback({
    required Map<String, Object?> arguments,
  }) async {
    final type = _optionalTrimmedString(arguments['type']) ?? 'light';
    return CapabilityExecutionResult(
      capabilityId: 'system.haptic_feedback',
      output: await _adapter.hapticFeedback(type),
    );
  }

  Future<CapabilityExecutionResult> playSystemSound({
    required Map<String, Object?> arguments,
  }) async {
    final type = _optionalTrimmedString(arguments['type']) ?? 'alert';
    return CapabilityExecutionResult(
      capabilityId: 'system.sound_alert',
      output: await _adapter.playSystemSound(type),
    );
  }

  Future<CapabilityExecutionResult> setMediaVolume({
    required Map<String, Object?> arguments,
  }) async {
    final rawLevel = arguments['level'];
    if (rawLevel is! num) {
      return const CapabilityExecutionResult(
        capabilityId: 'system.volume.set',
        output: {'ok': false, 'error': 'level is required'},
      );
    }
    final level = rawLevel.toDouble();
    if (level < 0 || level > 1) {
      return const CapabilityExecutionResult(
        capabilityId: 'system.volume.set',
        output: {'ok': false, 'error': 'level must be between 0 and 1'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'system.volume.set',
      output: await _adapter.setMediaVolume(level),
    );
  }

  Future<CapabilityExecutionResult> getMediaVolume() async {
    return CapabilityExecutionResult(
      capabilityId: 'system.volume.status',
      output: await _adapter.getMediaVolume(),
    );
  }

  Future<CapabilityExecutionResult> openPermissionSettings() async {
    return CapabilityExecutionResult(
      capabilityId: 'permission.open_settings',
      output: await _adapter.openPermissionSettings(),
    );
  }

  Future<CapabilityExecutionResult> openExternalUrl({
    required Map<String, Object?> arguments,
  }) async {
    final rawUrl = arguments['url'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'url.open_external',
        output: {'ok': false, 'error': 'url is required'},
      );
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return const CapabilityExecutionResult(
        capabilityId: 'url.open_external',
        output: {'ok': false, 'error': 'invalid url'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'url.open_external',
      output: await _adapter.openExternalUrl(uri),
    );
  }

  Future<CapabilityExecutionResult> setKeepScreenAwake({
    required Map<String, Object?> arguments,
  }) async {
    final enabled = arguments['enabled'];
    if (enabled is! bool) {
      return const CapabilityExecutionResult(
        capabilityId: 'screen.keep_awake',
        output: {'ok': false, 'error': 'enabled is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'screen.keep_awake',
      output: await _adapter.setKeepScreenAwake(enabled),
    );
  }

  Future<CapabilityExecutionResult> getKeepScreenAwake() async {
    return CapabilityExecutionResult(
      capabilityId: 'screen.keep_awake_status',
      output: await _adapter.getKeepScreenAwake(),
    );
  }

  Future<CapabilityExecutionResult> setScreenBrightness({
    required Map<String, Object?> arguments,
  }) async {
    final rawLevel = arguments['level'];
    if (rawLevel is! num) {
      return const CapabilityExecutionResult(
        capabilityId: 'screen.brightness.set',
        output: {'ok': false, 'error': 'level is required'},
      );
    }
    final level = rawLevel.toDouble();
    if (level < 0 || level > 1) {
      return const CapabilityExecutionResult(
        capabilityId: 'screen.brightness.set',
        output: {'ok': false, 'error': 'level must be between 0 and 1'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'screen.brightness.set',
      output: await _adapter.setScreenBrightness(level),
    );
  }

  Future<CapabilityExecutionResult> getScreenBrightness() async {
    return CapabilityExecutionResult(
      capabilityId: 'screen.brightness.status',
      output: await _adapter.getScreenBrightness(),
    );
  }

  Future<CapabilityExecutionResult> getScreenMetrics() async {
    return CapabilityExecutionResult(
      capabilityId: 'screen.metrics',
      output: await _adapter.getScreenMetrics(),
    );
  }

  Future<CapabilityExecutionResult> setScreenOrientation({
    required Map<String, Object?> arguments,
  }) async {
    final mode = _optionalTrimmedString(arguments['mode']);
    if (mode == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'screen.orientation.set',
        output: {'ok': false, 'error': 'mode is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'screen.orientation.set',
      output: await _adapter.setScreenOrientation(mode),
    );
  }

  Future<CapabilityExecutionResult> getScreenOrientation() async {
    return CapabilityExecutionResult(
      capabilityId: 'screen.orientation.status',
      output: await _adapter.getScreenOrientation(),
    );
  }

  Future<CapabilityExecutionResult> setSystemUiMode({
    required Map<String, Object?> arguments,
  }) async {
    final mode = _optionalTrimmedString(arguments['mode']);
    if (mode == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'system.ui.set',
        output: {'ok': false, 'error': 'mode is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'system.ui.set',
      output: await _adapter.setSystemUiMode(mode),
    );
  }

  Future<CapabilityExecutionResult> getSystemUiMode() async {
    return CapabilityExecutionResult(
      capabilityId: 'system.ui.status',
      output: await _adapter.getSystemUiMode(),
    );
  }

  Future<CapabilityExecutionResult> readAccelerometer() async {
    return CapabilityExecutionResult(
      capabilityId: 'sensor.accelerometer.read',
      output: await _adapter.readAccelerometer(),
    );
  }

  Future<CapabilityExecutionResult> readGyroscope() async {
    return CapabilityExecutionResult(
      capabilityId: 'sensor.gyroscope.read',
      output: await _adapter.readGyroscope(),
    );
  }

  Future<CapabilityExecutionResult> readMagnetometer() async {
    return CapabilityExecutionResult(
      capabilityId: 'sensor.magnetometer.read',
      output: await _adapter.readMagnetometer(),
    );
  }

  Future<CapabilityExecutionResult> getCurrentLocation() async {
    return CapabilityExecutionResult(
      capabilityId: 'location.get_current',
      output: await _adapter.getCurrentLocation(),
    );
  }

  Future<CapabilityExecutionResult> scheduleNotification({
    required Map<String, Object?> arguments,
  }) async {
    final rawTitle = arguments['title'];
    final rawBody = arguments['body'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'notification.schedule',
        output: {'ok': false, 'error': 'title is required'},
      );
    }
    if (rawBody is! String || rawBody.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'notification.schedule',
        output: {'ok': false, 'error': 'body is required'},
      );
    }

    final scheduledAt = _parseScheduledAt(arguments);
    if (scheduledAt == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'notification.schedule',
        output: {'ok': false, 'error': 'invalid scheduled_at'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'notification.schedule',
      output: await _adapter.scheduleNotification(
        title: rawTitle.trim(),
        body: rawBody.trim(),
        scheduledAt: scheduledAt,
      ),
    );
  }

  Future<CapabilityExecutionResult> listPendingNotifications() async {
    return CapabilityExecutionResult(
      capabilityId: 'notification.pending',
      output: await _adapter.listPendingNotifications(),
    );
  }

  Future<CapabilityExecutionResult> cancelNotification({
    required Map<String, Object?> arguments,
  }) async {
    final notificationId = _requiredPositiveInt(arguments['notification_id']);
    if (notificationId == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'notification.cancel',
        output: {'ok': false, 'error': 'notification_id is required'},
      );
    }
    return CapabilityExecutionResult(
      capabilityId: 'notification.cancel',
      output: await _adapter.cancelNotification(notificationId),
    );
  }

  Future<CapabilityExecutionResult> cancelAllNotifications() async {
    return CapabilityExecutionResult(
      capabilityId: 'notification.cancel_all',
      output: await _adapter.cancelAllNotifications(),
    );
  }

  Future<CapabilityExecutionResult> createCalendarEvent({
    required Map<String, Object?> arguments,
  }) async {
    final rawTitle = arguments['title'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      return const CapabilityExecutionResult(
        capabilityId: 'calendar.event.create',
        output: {'ok': false, 'error': 'title is required'},
      );
    }

    final startsAt = _parseIsoDateTime(arguments['start_at']);
    if (startsAt == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'calendar.event.create',
        output: {'ok': false, 'error': 'invalid start_at'},
      );
    }

    final endsAt = _parseCalendarEnd(arguments, startsAt);
    if (endsAt == null) {
      return const CapabilityExecutionResult(
        capabilityId: 'calendar.event.create',
        output: {'ok': false, 'error': 'invalid end_at'},
      );
    }

    return CapabilityExecutionResult(
      capabilityId: 'calendar.event.create',
      output: await _adapter.createCalendarEvent(
        title: rawTitle.trim(),
        description: _optionalTrimmedString(arguments['description']),
        location: _optionalTrimmedString(arguments['location']),
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: arguments['all_day'] == true,
      ),
    );
  }

  DateTime? _parseScheduledAt(Map<String, Object?> arguments) {
    final rawScheduledAt = arguments['scheduled_at'];
    if (rawScheduledAt is String && rawScheduledAt.trim().isNotEmpty) {
      return DateTime.tryParse(rawScheduledAt.trim())?.toLocal();
    }

    final rawDelaySeconds = arguments['delay_seconds'];
    final delaySeconds = rawDelaySeconds is num
        ? rawDelaySeconds.clamp(1, 31536000).round()
        : 60;
    return DateTime.now().add(Duration(seconds: delaySeconds));
  }

  DateTime? _parseCalendarEnd(
    Map<String, Object?> arguments,
    DateTime startsAt,
  ) {
    final explicitEnd = _parseIsoDateTime(arguments['end_at']);
    if (explicitEnd != null) {
      return explicitEnd;
    }

    final rawDurationMinutes = arguments['duration_minutes'];
    final durationMinutes = rawDurationMinutes is num
        ? rawDurationMinutes.clamp(1, 1440).round()
        : 60;
    return startsAt.add(Duration(minutes: durationMinutes));
  }

  DateTime? _parseIsoDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  String? _optionalTrimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _optionalPositiveDouble(Object? value) {
    if (value is! num || value <= 0) {
      return null;
    }
    return value.toDouble();
  }

  int? _optionalImageQuality(Object? value) {
    if (value is! num) {
      return null;
    }
    return value.clamp(1, 100).round();
  }

  int? _requiredPositiveInt(Object? value) {
    if (value is num && value > 0) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  Duration? _optionalDuration(Object? value) {
    if (value is! num || value <= 0) {
      return null;
    }
    return Duration(seconds: value.clamp(1, 3600).round());
  }

  List<String> _stringList(Object? value) {
    if (value is! Iterable<Object?>) {
      return const [];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}
