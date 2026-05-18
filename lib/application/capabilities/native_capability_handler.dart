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
}
