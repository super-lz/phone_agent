import 'dart:convert';

import 'capability_result_presentation.dart';

class CapabilityExecutionResult {
  const CapabilityExecutionResult({
    required this.capabilityId,
    required this.output,
  });

  final String capabilityId;
  final Map<String, Object?> output;

  CapabilityExecutionResult copyWithOutput(Map<String, Object?> nextOutput) {
    return CapabilityExecutionResult(
      capabilityId: capabilityId,
      output: nextOutput,
    );
  }

  CapabilityExecutionResult withReceipt({
    required String actionId,
    required String argumentsHash,
    bool replayed = false,
    bool replayProtected = false,
    String? duplicateOf,
  }) {
    final nextOutput = Map<String, Object?>.from(output);
    final receipt = <String, Object?>{
      'actionId': actionId,
      'status': _receiptStatus(nextOutput),
      'effect': _effectFor(capabilityId, nextOutput),
      'replayed': replayed,
      'replayProtected': replayProtected,
      'argumentsHash': argumentsHash,
    };
    if (duplicateOf != null) {
      receipt['duplicateOf'] = duplicateOf;
    }
    final resource = _resourceFor(nextOutput);
    if (resource != null) {
      receipt['resource'] = resource;
    }
    nextOutput['receipt'] = receipt;
    return copyWithOutput(nextOutput);
  }

  String get encodedOutput {
    return jsonEncode(output);
  }

  String get encodedModelObservation {
    return jsonEncode(
      modelObservationForCapability(capabilityId: capabilityId, output: output),
    );
  }

  static String _receiptStatus(Map<String, Object?> output) {
    if (output['ok'] == true) {
      return 'completed';
    }
    if (output['error'] == 'permission_confirmation_required' ||
        output['error'] == 'pending') {
      return 'pending';
    }
    return 'failed';
  }

  static String _effectFor(String capabilityId, Map<String, Object?> output) {
    if (output['ok'] != true) {
      return _receiptStatus(output);
    }
    final normalized = capabilityId.toLowerCase();
    if (normalized.contains('create') || normalized.contains('generate')) {
      return 'created';
    }
    if (normalized.contains('update') ||
        normalized.contains('patch') ||
        normalized.contains('set') ||
        normalized.contains('write') ||
        normalized.contains('switch') ||
        normalized.contains('revert')) {
      return 'updated';
    }
    if (normalized.contains('delete') || normalized.contains('cancel')) {
      return 'deleted';
    }
    return 'read';
  }

  static Map<String, Object?>? _resourceFor(Map<String, Object?> output) {
    const candidates = <String>[
      'artifactId',
      'fileId',
      'memoryId',
      'noteId',
      'activeWorkspaceId',
      'notificationId',
    ];
    for (final key in candidates) {
      final id = output[key];
      if (id is String && id.isNotEmpty) {
        return {'type': key.replaceFirst('Id', ''), 'id': id};
      }
    }
    return null;
  }
}
