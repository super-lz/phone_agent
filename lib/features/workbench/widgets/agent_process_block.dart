import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../application/agent/tool_display_names.dart';
import '../../../domain/conversation/message_block.dart';
import 'agent_process_entries.dart';
import 'tool_step_view.dart';

typedef AgentProcessBlockBuilder = Widget Function(MessageBlock block);

class AgentProcessBlock extends StatefulWidget {
  const AgentProcessBlock({
    required this.blocks,
    required this.status,
    required this.blockBuilder,
    this.currentRun,
    super.key,
  });

  final List<MessageBlock> blocks;
  final String status;
  final AgentRunSnapshot? currentRun;
  final AgentProcessBlockBuilder blockBuilder;

  @override
  State<AgentProcessBlock> createState() => _AgentProcessBlockState();
}

class _AgentProcessBlockState extends State<AgentProcessBlock> {
  late bool _expanded = widget.status == 'processing';

  @override
  void didUpdateWidget(AgentProcessBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _expanded = widget.status == 'processing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final entries = agentProcessEntries(widget.blocks);
    final steps = entries.whereType<ToolStepEntry>().toList(growable: false);
    // Approval must remain reachable when the runtime's completed checkpoint
    // collapses the execution trace. Render each pending request only once.
    final approvals = entries
        .whereType<ProcessContentEntry>()
        .where(
          (entry) =>
              entry.block.type == MessageBlockType.approvalRequest &&
              (entry.block.data['status'] ?? 'pending') == 'pending',
        )
        .toList(growable: false);
    final title = _statusTitle(steps, approvals.isNotEmpty);
    final hasIssue = steps.any(
      (step) => switch (step.status(widget.status)) {
        ToolStepStatus.failed ||
        ToolStepStatus.unknown ||
        ToolStepStatus.denied ||
        ToolStepStatus.waiting ||
        ToolStepStatus.authorized => true,
        _ => false,
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    hasIssue
                        ? Icons.info_outline_rounded
                        : approvals.isNotEmpty
                        ? Icons.lock_outline_rounded
                        : widget.status == 'processing'
                        ? Icons.more_horiz
                        : widget.status == 'stopped'
                        ? Icons.remove_rounded
                        : Icons.check_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
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
              margin: const EdgeInsets.only(left: 9, top: 2, bottom: 4),
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < entries.length; index++)
                    switch (entries[index]) {
                      final ToolStepEntry step => ToolStepView(
                        key: ValueKey(index),
                        entry: step,
                        processStatus: widget.status,
                      ),
                      final ProcessContentEntry content =>
                        approvals.contains(content)
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: widget.blockBuilder(content.block),
                              ),
                    },
                ],
              ),
            ),
          for (final approval in approvals) ...[
            const SizedBox(height: 8),
            widget.blockBuilder(approval.block),
          ],
        ],
      ),
    );
  }

  String _statusTitle(List<ToolStepEntry> steps, bool needsApproval) {
    if (needsApproval) return '等待授权';
    if (widget.status == 'stopped') return '已停止';
    final run = widget.currentRun;
    if (run != null && run.isActive) {
      if (run.phase == AgentRunPhase.waitingForToolCall) {
        final name = run.currentToolName;
        return name == null
            ? '正在生成工具参数'
            : '正在生成参数 · ${agentToolDisplayName(name)}';
      }
      if (run.phase == AgentRunPhase.waitingForeground) return '等待回到前台';
      if (run.phase == AgentRunPhase.finalizing) return '正在整理回答';
    }
    if (widget.status == 'processing') {
      final running = steps.where(
        (step) => step.status(widget.status) == ToolStepStatus.running,
      );
      if (running.isNotEmpty) {
        return '正在执行 ${agentToolDisplayName(running.last.toolName)}';
      }
      return steps.isEmpty ? '正在思考...' : '正在整理工具结果';
    }
    final states = steps.map((step) => step.status(widget.status)).toSet();
    for (final state in [
      ToolStepStatus.failed,
      ToolStepStatus.unknown,
      ToolStepStatus.denied,
      ToolStepStatus.waiting,
      ToolStepStatus.authorized,
    ]) {
      if (states.contains(state)) return '执行过程 · ${toolStepStatusLabel(state)}';
    }
    if (steps.isEmpty) return '已处理';
    if (steps.length == 1) {
      return '已完成 ${agentToolDisplayName(steps.single.toolName)}';
    }
    return '已完成 ${steps.length} 个步骤';
  }
}
