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
        return '正在执行 ${_toolLabel(_toolName(toolCallBlocks.last))}';
      }
      return '正在整理工具结果';
    }
    if (toolCalls == 0) {
      return '已处理';
    }
    if (toolCalls == 1) {
      return '已完成 ${_toolLabel(_toolName(toolCallBlocks.single))}';
    }
    return '已完成 $toolCalls 个步骤';
  }

  String _toolName(MessageBlock block) {
    return block.data['capabilityId'] as String? ?? 'tool';
  }

  String _toolLabel(String name) {
    return switch (name) {
      'project_create_web_app' => '创建 Web App',
      'project_update_web_app' => '更新 Web App',
      'project_test_web_app' => '检查 Web App',
      'artifact_create' => '创建 Artifact',
      'artifact_query' => '查询 Artifact',
      'file_write_app_file' => '写入文件',
      'file_read_app_file' => '读取文件',
      'file_search_app_files' => '搜索文件',
      'web_search' => '联网搜索',
      'web_fetch' => '读取网页',
      _ => name.replaceAll('_', ' '),
    };
  }
}
