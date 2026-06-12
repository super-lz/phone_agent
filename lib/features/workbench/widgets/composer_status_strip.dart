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
  static const _suggestions = ['帮我创建一个待办 Web App', '总结当前工作区文件', '记录一个今天的想法'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
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
    );
  }

  void _copySuggestion(String value) {
    final text = _withoutTrailingFullStops(value);
    controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    Clipboard.setData(ClipboardData(text: text));
  }
}

String _withoutTrailingFullStops(String value) {
  return value.trimRight().replaceFirst(RegExp(r'。+$'), '');
}

class _RunStepSummary extends StatelessWidget {
  const _RunStepSummary({required this.run, super.key});

  final AgentRunSnapshot run;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _withoutTrailingFullStops(run.detail),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: colors.primaryAction,
          letterSpacing: 0,
        ),
      ),
    );
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final suggestion in suggestions) ...[
            _SuggestionChip(suggestion: suggestion, onPick: onPick),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.onPick});

  final String suggestion;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final label = _withoutTrailingFullStops(suggestion);
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: colors.inputBackground.withValues(alpha: 0.72),
      side: BorderSide(color: colors.border.withValues(alpha: 0.72)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: colors.textSecondary,
          letterSpacing: 0,
        ),
      ),
      onPressed: () => onPick(label),
    );
  }
}
