import 'package:flutter/material.dart';

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
    final summary = _summary(widget.blocks);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE3D8)),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(), size: 18, color: const Color(0xFF787F76)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusTitle(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF6F766D),
                      ),
                    ),
                  ),
                  Text(summary, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                for (final block in widget.blocks) widget.blockBuilder(block),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon() {
    return widget.status == 'processing'
        ? Icons.more_horiz
        : Icons.check_circle_outline;
  }

  String _statusTitle() {
    return widget.status == 'processing' ? '处理中' : '已处理';
  }

  String _summary(List<MessageBlock> blocks) {
    final toolCalls = blocks
        .where((block) => block.type == MessageBlockType.toolCall)
        .length;
    final toolResults = blocks
        .where((block) => block.type == MessageBlockType.toolResult)
        .length;
    final contentBlocks = blocks
        .where(
          (block) =>
              block.type == MessageBlockType.markdownText ||
              block.type == MessageBlockType.codeBlock ||
              block.type == MessageBlockType.todoList,
        )
        .length;
    final parts = <String>[];
    if (toolCalls > 0) {
      parts.add('$toolCalls 次调用');
    }
    if (toolResults > 0) {
      parts.add('$toolResults 个结果');
    }
    if (contentBlocks > 0) {
      parts.add('$contentBlocks 段中间输出');
    }
    return parts.isEmpty ? '详情' : parts.join(' · ');
  }
}
