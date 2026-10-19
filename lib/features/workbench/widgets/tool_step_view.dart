import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/tool_display_names.dart';
import '../../../application/capabilities/capability_result_presentation.dart';
import 'agent_process_entries.dart';
import 'tool_call_summary.dart';
import 'tool_result_view.dart';

class ToolStepView extends StatefulWidget {
  const ToolStepView({
    required this.entry,
    required this.processStatus,
    super.key,
  });

  final ToolStepEntry entry;
  final String processStatus;

  @override
  State<ToolStepView> createState() => _ToolStepViewState();
}

class _ToolStepViewState extends State<ToolStepView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final entry = widget.entry;
    final status = entry.status(widget.processStatus);
    final attention = switch (status) {
      ToolStepStatus.failed || ToolStepStatus.unknown => true,
      _ => false,
    };
    final color = attention ? const Color(0xFFBF503D) : colors.textSecondary;
    final target = toolCallTarget(entry.call?.data['input']);
    final output = entry.result?.data['output'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: status == ToolStepStatus.running
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: colors.primaryAction,
                          ),
                        )
                      : Icon(_statusIcon(status), size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agentToolDisplayName(entry.toolName),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (target != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          target,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      if (status != ToolStepStatus.completed) ...[
                        const SizedBox(height: 3),
                        Text(
                          toolStepStatusLabel(status),
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(left: 11, bottom: 8),
            padding: const EdgeInsets.fromLTRB(15, 6, 4, 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.call != null) ...[
                  SelectableText(
                    toolCallSummary(entry.toolName, entry.call!.data['input']),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (output != null) const SizedBox(height: 12),
                ],
                if (output is Map<String, Object?>)
                  _StepResult(entry: entry, output: output, status: status),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepResult extends StatelessWidget {
  const _StepResult({
    required this.entry,
    required this.output,
    required this.status,
  });

  final ToolStepEntry entry;
  final Map<String, Object?> output;
  final ToolStepStatus status;

  @override
  Widget build(BuildContext context) {
    final capabilityId = canonicalProcessToolName(entry.toolName);
    final needsDistinctOutcome = switch (status) {
      ToolStepStatus.waiting ||
      ToolStepStatus.authorized ||
      ToolStepStatus.denied ||
      ToolStepStatus.unknown => true,
      _ => false,
    };
    if (!needsDistinctOutcome) {
      return ToolResultView(
        capabilityId: capabilityId,
        output: output,
        showFrame: false,
      );
    }
    final detail = output['userMessage'] ?? output['detail'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          status == ToolStepStatus.authorized
              ? '已获得授权，实际执行结果以后续步骤为准。'
              : detail is String
              ? detail
              : toolStepStatusLabel(status),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('执行回执', style: TextStyle(fontSize: 12)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          dense: true,
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            SelectableText(
              presentCapabilityResult(
                capabilityId: capabilityId,
                output: output,
              ).detail,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }
}

String toolStepStatusLabel(ToolStepStatus status) => switch (status) {
  ToolStepStatus.running => '执行中',
  ToolStepStatus.completed => '已完成',
  ToolStepStatus.waiting => '等待授权',
  ToolStepStatus.authorized => '已授权',
  ToolStepStatus.denied => '已拒绝',
  ToolStepStatus.failed => '执行失败',
  ToolStepStatus.unknown => '结果未知',
  ToolStepStatus.stopped => '已停止等待结果',
};

IconData _statusIcon(ToolStepStatus status) => switch (status) {
  ToolStepStatus.completed => Icons.check_rounded,
  ToolStepStatus.waiting => Icons.lock_outline_rounded,
  ToolStepStatus.authorized => Icons.verified_user_outlined,
  ToolStepStatus.denied => Icons.block_outlined,
  ToolStepStatus.failed => Icons.error_outline_rounded,
  ToolStepStatus.unknown => Icons.help_outline_rounded,
  ToolStepStatus.stopped => Icons.remove_rounded,
  ToolStepStatus.running => Icons.more_horiz,
};
