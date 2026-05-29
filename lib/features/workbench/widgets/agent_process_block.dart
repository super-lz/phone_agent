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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.status == 'processing')
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.grey),
                      ),
                    )
                  else
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusTitle(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 20),
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
      return toolCalls > 0 ? '正在调用工具 ($toolCalls)...' : '正在思考...';
    }
    return toolCalls > 0 ? '已使用 $toolCalls 个工具' : '已思考完成';
  }
}
