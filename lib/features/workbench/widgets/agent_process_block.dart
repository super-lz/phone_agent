import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/tool_display_names.dart';
import '../../../domain/conversation/message_block.dart';

typedef AgentProcessBlockBuilder = Widget Function(MessageBlock block);

class AgentProcessBlock extends StatefulWidget {
  const AgentProcessBlock({
    required this.blocks,
    required this.status,
    required this.blockBuilder,
    super.key,
  });

  final List<MessageBlock> blocks;
  final String status;
  final AgentProcessBlockBuilder blockBuilder;

  @override
  State<AgentProcessBlock> createState() => _AgentProcessBlockState();
}

class _AgentProcessBlockState extends State<AgentProcessBlock> {
  late bool _expanded = widget.status == 'processing';

  @override
  void didUpdateWidget(AgentProcessBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) {
      return;
    }
    _expanded = widget.status == 'processing';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final splitColor = colors.border.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (widget.status == 'processing')
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          colors.primaryAction,
                        ),
                      ),
                    )
                  else
                    Icon(
                      widget.status == 'stopped'
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusTitle(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 16, thickness: 0.5, color: splitColor),
            for (var index = 0; index < widget.blocks.length; index += 1) ...[
              widget.blockBuilder(widget.blocks[index]),
              if (index != widget.blocks.length - 1)
                Divider(height: 12, thickness: 0.4, color: splitColor),
            ],
          ],
        ],
      ),
    );
  }

  String _statusTitle() {
    final toolCallBlocks = widget.blocks
        .where((block) => block.type == MessageBlockType.toolCall)
        .toList(growable: false);
    final toolCalls = toolCallBlocks.length;
    final toolResults = widget.blocks
        .where((block) => block.type == MessageBlockType.toolResult)
        .length;
    if (widget.status == 'processing') {
      if (toolCalls == 0) {
        return '正在思考...';
      }
      if (toolResults < toolCalls) {
        return '正在执行 ${agentToolDisplayName(_toolName(toolCallBlocks.last))}';
      }
      return '正在整理工具结果';
    }
    if (widget.status == 'stopped') {
      return '已停止';
    }
    if (toolCalls == 0) {
      return '已处理';
    }
    if (toolCalls == 1) {
      return '已完成 ${agentToolDisplayName(_toolName(toolCallBlocks.single))}';
    }
    return '已完成 $toolCalls 个步骤';
  }

  String _toolName(MessageBlock block) {
    return block.data['capabilityId'] as String? ?? 'tool';
  }
}
