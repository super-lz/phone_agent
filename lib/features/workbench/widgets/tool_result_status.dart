import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

class ToolResultStatus extends StatelessWidget {
  const ToolResultStatus({required this.ok, super.key});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ok ? colors.cardBackground : colors.warningBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          ok ? '成功' : '失败',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ok ? colors.statusText : const Color(0xFFE0523D),
          ),
        ),
      ),
    );
  }
}
