import 'dart:convert';

class CapabilityExecutionResult {
  const CapabilityExecutionResult({
    required this.capabilityId,
    required this.output,
  });

  final String capabilityId;
  final Map<String, Object?> output;

  String get encodedOutput {
    return jsonEncode(output);
  }
}
