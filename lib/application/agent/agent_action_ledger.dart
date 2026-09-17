import 'dart:convert';

import '../../data/models/openai_compatible_chat_client.dart';
import '../capabilities/capability_execution_result.dart';

/// The lifecycle of a logical user action. It is deliberately independent of
/// a tool name: one action may be implemented by a built-in capability, MCP,
/// or a future adapter.
enum AgentActionStatus { running, completed, pending, failed }

class AgentActionRecord {
  AgentActionRecord({
    required this.actionId,
    required this.callId,
    required this.capabilityId,
    required this.fingerprint,
    required this.status,
    this.result,
  });

  final String actionId;
  final String callId;
  final String capabilityId;
  final String fingerprint;
  AgentActionStatus status;
  CapabilityExecutionResult? result;
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
