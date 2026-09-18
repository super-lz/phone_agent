import 'dart:convert';

import '../../data/models/openai_compatible_chat_client.dart';
import '../capabilities/capability_execution_result.dart';

/// The lifecycle of a logical user action. It is deliberately independent of
/// a tool name: one action may be implemented by a built-in capability, MCP,
/// or a future adapter.
enum AgentActionStatus { running, completed, pending, failed, resultUnknown }

class AgentActionRecord {
  AgentActionRecord({
    required this.actionId,
    required this.callId,
    required this.capabilityId,
    required this.fingerprint,
    required this.status,
    required this.deduplicate,
    this.result,
  });

  final String actionId;
  final String callId;
  final String capabilityId;
  final String fingerprint;
  AgentActionStatus status;
  final bool deduplicate;
  CapabilityExecutionResult? result;

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'callId': callId,
    'capabilityId': capabilityId,
    'fingerprint': fingerprint,
    'status': status.name,
    'deduplicate': deduplicate,
    if (result != null)
      'result': {
        'capabilityId': result!.capabilityId,
        'output': result!.output,
      },
  };

  static AgentActionRecord fromJson(Map<String, Object?> json) {
    final rawResult = json['result'];
    final rawOutput = rawResult is Map ? rawResult['output'] : null;
    final result =
        rawResult is Map &&
            rawResult['capabilityId'] is String &&
            rawOutput is Map
        ? CapabilityExecutionResult(
            capabilityId: rawResult['capabilityId'] as String,
            output: rawOutput.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null;
    final statusName = json['status'] as String?;
    final storedStatus = AgentActionStatus.values
        .where((status) => status.name == statusName)
        .firstOrNull;
    return AgentActionRecord(
      actionId: json['actionId']! as String,
      callId: json['callId']! as String,
      capabilityId: json['capabilityId']! as String,
      fingerprint: json['fingerprint']! as String,
      // A process can die after an action was marked running but before its
      // adapter returned. Treat that as unknown; never retry it blindly.
      status: storedStatus == null || storedStatus == AgentActionStatus.running
          ? AgentActionStatus.resultUnknown
          : storedStatus,
      deduplicate: json['deduplicate'] != false,
      result: result,
    );
  }
}

class AgentActionDecision {
  const AgentActionDecision({
    required this.record,
    this.replayedResult,
    this.duplicateOf,
  });

  final AgentActionRecord record;
  final CapabilityExecutionResult? replayedResult;
  final String? duplicateOf;

  bool get requiresResolution =>
      record.status == AgentActionStatus.resultUnknown &&
      replayedResult == null;

  bool get isReplay => replayedResult != null;
}

/// Per-agent-run ledger used to make side effects converge.
///
/// A new run gets a new ledger, so an explicit new user request can perform
/// the same action again. Inside one run, an identical completed action is a
/// replay and is never executed a second time.
class AgentActionLedger {
  final Map<String, AgentActionRecord> _byFingerprint = {};
  final Map<String, AgentActionRecord> _byCallId = {};
  final Map<String, AgentActionRecord> _records = {};
  int _nextActionNumber = 0;

  AgentActionLedger();

  factory AgentActionLedger.fromJson(Object? value) {
    final ledger = AgentActionLedger();
    if (value is! Iterable) {
      return ledger;
    }
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final record = AgentActionRecord.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      ledger._records[record.actionId] = record;
      ledger._byCallId[record.callId] = record;
      if (record.deduplicate) {
        ledger._byFingerprint[record.fingerprint] = record;
      }
      final match = RegExp(r'^action-(\d+)$').firstMatch(record.actionId);
      final sequence = match == null ? null : int.tryParse(match.group(1)!);
      if (sequence != null && sequence > ledger._nextActionNumber) {
        ledger._nextActionNumber = sequence;
      }
    }
    return ledger;
  }

  List<Map<String, Object?>> toJson() =>
      _records.values.map((record) => record.toJson()).toList(growable: false);

  AgentActionDecision begin({
    required ToolCallRequest toolCall,
    required String capabilityId,
    bool deduplicate = true,
  }) {
    final callIdRecord = _byCallId[toolCall.id];
    if (callIdRecord != null) {
      return AgentActionDecision(
        record: callIdRecord,
        replayedResult: callIdRecord.result,
        duplicateOf: callIdRecord.actionId,
      );
    }

    final fingerprint = actionFingerprint(
      capabilityId: capabilityId,
      arguments: toolCall.arguments,
    );
    final previous = deduplicate ? _byFingerprint[fingerprint] : null;
    if (previous != null &&
        previous.result == null &&
        (previous.status == AgentActionStatus.running ||
            previous.status == AgentActionStatus.resultUnknown)) {
      return AgentActionDecision(
        record: previous,
        duplicateOf: previous.actionId,
      );
    }
    if (previous != null &&
        previous.result != null &&
        previous.status != AgentActionStatus.failed) {
      _byCallId[toolCall.id] = previous;
      return AgentActionDecision(
        record: previous,
        replayedResult: previous.result,
        duplicateOf: previous.actionId,
      );
    }

    final explicitActionId = toolCall.arguments['_agentActionId'];
    final actionId = explicitActionId is String && explicitActionId.isNotEmpty
        ? explicitActionId
        : 'action-${++_nextActionNumber}';
    final record = AgentActionRecord(
      actionId: actionId,
      callId: toolCall.id,
      capabilityId: capabilityId,
      fingerprint: fingerprint,
      status: AgentActionStatus.running,
      deduplicate: deduplicate,
    );
    _byCallId[toolCall.id] = record;
    _records[actionId] = record;
    if (deduplicate) {
      _byFingerprint[fingerprint] = record;
    }
    return AgentActionDecision(record: record);
  }

  void complete(AgentActionRecord record, CapabilityExecutionResult result) {
    record.result = result;
    record.status = _statusFor(result);
  }

  Iterable<AgentActionRecord> get records => _records.values;

  List<Map<String, Object?>> get modelCheckpoint => [
    for (final record in records)
      {
        'actionId': record.actionId,
        'capabilityId': record.capabilityId,
        'status': record.status.name,
        if (record.result != null) 'output': record.result!.output,
      },
  ];

  static AgentActionStatus _statusFor(CapabilityExecutionResult result) {
    if (result.output['ok'] == true) {
      return AgentActionStatus.completed;
    }
    if (result.output['error'] == 'permission_confirmation_required' ||
        result.output['error'] == 'pending') {
      return AgentActionStatus.pending;
    }
    return AgentActionStatus.failed;
  }
}

class AgentExecutionContext {
  const AgentExecutionContext({
    required this.runId,
    required this.round,
    required this.ledger,
  });

  final String runId;
  final int round;
  final AgentActionLedger ledger;
}

/// Stable enough for a single run and human-auditable in logs. The hash is
/// intentionally dependency-free; the canonical JSON is also available when
/// diagnosing a collision.
String actionFingerprint({
  required String capabilityId,
  required Map<String, Object?> arguments,
}) {
  final canonicalArguments = canonicalJson(
    _withoutInternalArguments(arguments),
  );
  final explicitActionId = arguments['_agentActionId'];
  final actionScope = explicitActionId is String && explicitActionId.isNotEmpty
      ? 'action:$explicitActionId|'
      : '';
  return '$capabilityId:${fnv1a64('$actionScope$canonicalArguments')}';
}

String canonicalJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(canonicalJson).join(',')}]';
  }
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return '{${entries.map((entry) => '${jsonEncode(entry.key)}:${canonicalJson(entry.value)}').join(',')}}';
  }
  return jsonEncode(value.toString());
}

String fnv1a64(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Map<String, Object?> _withoutInternalArguments(Map<String, Object?> arguments) {
  return Map<String, Object?>.fromEntries(
    arguments.entries.where((entry) => entry.key != '_agentActionId'),
  );
}
