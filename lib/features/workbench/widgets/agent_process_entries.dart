import '../../../application/capabilities/capability_runtime.dart';
import '../../../domain/conversation/message_block.dart';

enum ToolStepStatus {
  running,
  completed,
  waiting,
  authorized,
  denied,
  failed,
  unknown,
  stopped,
}

sealed class AgentProcessEntry {
  const AgentProcessEntry();
}

final class ProcessContentEntry extends AgentProcessEntry {
  const ProcessContentEntry(this.block);

  final MessageBlock block;
}

final class ToolStepEntry extends AgentProcessEntry {
  const ToolStepEntry({this.call, this.result, this.approvalStatus});

  final MessageBlock? call;
  final MessageBlock? result;
  final String? approvalStatus;

  String get toolName =>
      (call ?? result)!.data['capabilityId'] as String? ?? 'tool';

  ToolStepStatus status(String processStatus) {
    final output = result?.data['output'];
    if (output is Map<String, Object?>) {
      final receipt = output['receipt'];
      final receiptStatus = receipt is Map<Object?, Object?>
          ? receipt['status']
          : null;
      if (output['error'] == 'action_result_unknown' ||
          receiptStatus == 'result_unknown') {
        return ToolStepStatus.unknown;
      }
      if (output['error'] == 'permission_confirmation_required') {
        return switch (approvalStatus) {
          'approved' => ToolStepStatus.authorized,
          'denied' => ToolStepStatus.denied,
          _ => ToolStepStatus.waiting,
        };
      }
      if (output['error'] == 'permission_denied') {
        return ToolStepStatus.denied;
      }
      return output['ok'] == true
          ? ToolStepStatus.completed
          : ToolStepStatus.failed;
    }
    return switch (processStatus) {
      'processing' => ToolStepStatus.running,
      'stopped' => ToolStepStatus.stopped,
      _ => ToolStepStatus.unknown,
    };
  }
}

String canonicalProcessToolName(String name) =>
    CapabilityRuntime.capabilityIdForToolName(name) ?? name;

List<AgentProcessEntry> agentProcessEntries(List<MessageBlock> blocks) {
  final entries = <AgentProcessEntry>[];
  for (final block in blocks) {
    if (block.type == MessageBlockType.toolCall) {
      entries.add(ToolStepEntry(call: block));
    } else if (block.type == MessageBlockType.toolResult) {
      final name = canonicalProcessToolName(
        block.data['capabilityId'] as String? ?? 'tool',
      );
      // Persisted UI blocks have no call ID. The runtime emits calls serially,
      // so consume the earliest unmatched call instead of reusing a result.
      final index = entries.indexWhere(
        (entry) =>
            entry is ToolStepEntry &&
            entry.call != null &&
            entry.result == null &&
            canonicalProcessToolName(entry.toolName) == name,
      );
      if (index < 0) {
        entries.add(ToolStepEntry(result: block));
      } else {
        entries[index] = ToolStepEntry(
          call: (entries[index] as ToolStepEntry).call,
          result: block,
        );
      }
    } else {
      if (block.type == MessageBlockType.approvalRequest) {
        final name = canonicalProcessToolName(
          block.data['toolName'] as String? ??
              block.data['capabilityId'] as String? ??
              'tool',
        );
        final index = entries.lastIndexWhere(
          (entry) =>
              entry is ToolStepEntry &&
              canonicalProcessToolName(entry.toolName) == name &&
              entry.status('completed') == ToolStepStatus.waiting,
        );
        if (index >= 0) {
          final entry = entries[index] as ToolStepEntry;
          entries[index] = ToolStepEntry(
            call: entry.call,
            result: entry.result,
            approvalStatus: block.data['status'] as String?,
          );
        }
      }
      entries.add(ProcessContentEntry(block));
    }
  }
  return List.unmodifiable(entries);
}
