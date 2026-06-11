import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/agent/agent_run_state.dart';
import '../../../application/agent/context_budget.dart';
import 'context_budget_ring.dart';

class ComposerStatusStrip extends StatelessWidget {
  const ComposerStatusStrip({
    required this.controller,
    required this.isSending,
    required this.currentRun,
    required this.contextBudget,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final AgentRunSnapshot? currentRun;
  final ContextBudgetSnapshot? contextBudget;

  static const _contentLeftInset = 12.0;
  static const _dividerHorizontalInset = 16.0;
  static const _suggestions = ['帮我创建一个待办 Web App', '总结当前工作区文件', '记录一个今天的想法'];

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Positioned(
            left: _dividerHorizontalInset,
            right: _dividerHorizontalInset,
            bottom: 0,
            child: ColoredBox(
              color: colors.border.withValues(alpha: 0.38),
              child: const SizedBox(height: 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: _contentLeftInset, bottom: 6),
            child: Row(
              children: [
                ContextBudgetRing(budget: contextBudget),
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: isSending && currentRun != null
                        ? _RunStepSummary(
                            key: const ValueKey('run'),
                            run: currentRun!,
                          )
                        : _SuggestionStrip(
                            key: const ValueKey('suggestions'),
                            suggestions: _suggestions,
                            onPick: (value) => _copySuggestion(value),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copySuggestion(String value) {
    controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    Clipboard.setData(ClipboardData(text: value));
  }
}

class _RunStepSummary extends StatelessWidget {
  const _RunStepSummary({required this.run, super.key});

  final AgentRunSnapshot run;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(colors.primaryAction),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _title(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryAction,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                run.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _title() {
    final toolName = run.currentToolName;
    if (toolName != null && toolName.isNotEmpty) {
      return '${run.phaseLabel} · ${_toolLabel(toolName)}';
    }
    return run.phaseLabel;
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

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.suggestions,
    required this.onPick,
    super.key,
  });

  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final suggestion in suggestions) ...[
            ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: colors.inputBackground.withValues(alpha: 0.72),
              side: BorderSide(color: colors.border.withValues(alpha: 0.72)),
              label: Text(
                suggestion,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  letterSpacing: 0,
                ),
              ),
              onPressed: () => onPick(suggestion),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
