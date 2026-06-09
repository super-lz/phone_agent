import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                      Icons.check_circle_outline,
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
              if (_expanded) ...[
                Divider(height: 20, color: colors.border),
                for (final block in widget.blocks) widget.blockBuilder(block),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusTitle() {
    final toolCalls = widget.blocks
        .where((block) => block.type == MessageBlockType.toolCall)
        .length;
    if (widget.status == 'processing') {
      return toolCalls > 0 ? '正在处理 ($toolCalls 个工具)...' : '正在思考...';
    }
    return toolCalls > 0 ? '已处理 ($toolCalls 个工具)' : '已处理';
  }
}
