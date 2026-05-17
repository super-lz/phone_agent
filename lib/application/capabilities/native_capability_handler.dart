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
}
