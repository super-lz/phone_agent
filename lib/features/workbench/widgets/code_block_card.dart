import 'package:flutter/material.dart';

class CodeBlockCard extends StatefulWidget {
  const CodeBlockCard({
    required this.language,
    required this.code,
    this.initiallyExpanded,
    this.showCollapsedPreview = true,
    super.key,
  });

  final String language;
  final String code;
  final bool? initiallyExpanded;
  final bool showCollapsedPreview;

  @override
  State<CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<CodeBlockCard> {
  late bool _expanded = _initialExpanded();
  bool _userToggled = false;

  @override
  void didUpdateWidget(CodeBlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.code != widget.code ||
            oldWidget.initiallyExpanded != widget.initiallyExpanded) &&
        !_userToggled) {
      _expanded = _initialExpanded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              _userToggled = true;
              _expanded = !_expanded;
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 16, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.language.isEmpty ? '代码' : widget.language,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '$lineCount 行',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SelectionArea(
                child: Text(
                  widget.code,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.showCollapsedPreview
                  ? Text(
                      _preview(widget.code),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                      ),
                    )
                  : const Text(
                      '代码已折叠，点击展开查看。',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  bool _initialExpanded() {
    return widget.initiallyExpanded ?? !_shouldCollapse(widget.code);
  }

  bool _shouldCollapse(String code) {
    return code.length > 800 || '\n'.allMatches(code).length >= 12;
  }

  String _preview(String code) {
    final lines = code.trim().split('\n').take(3).join('\n');
    if (lines.isEmpty) {
      return '空代码块';
    }
    if (lines.length > 360) {
      return '${lines.substring(0, 360)}...';
    }
    return lines;
  }
}
