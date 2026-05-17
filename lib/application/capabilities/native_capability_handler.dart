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
}
