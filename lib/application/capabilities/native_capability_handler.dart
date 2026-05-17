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

  Future<CapabilityExecutionResult> readClipboard() async {
    return CapabilityExecutionResult(
      capabilityId: 'clipboard.read',
      output: await _adapter.readClipboard(),
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
