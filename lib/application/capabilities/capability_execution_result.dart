import 'dart:convert';

import 'capability_result_presentation.dart';

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

  String get encodedModelObservation {
    return jsonEncode(
      modelObservationForCapability(capabilityId: capabilityId, output: output),
    );
  }
}
