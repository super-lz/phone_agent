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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF17211B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              _userToggled = true;
              _expanded = !_expanded;
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 18, color: Color(0xFF9CCFB5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.language.isEmpty ? 'code' : widget.language,
                      style: const TextStyle(color: Color(0xFF9CCFB5)),
                    ),
                  ),
                  Text(
                    '$lineCount 行',
                    style: const TextStyle(color: Color(0xFF9CCFB5)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CCFB5),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.showCollapsedPreview
                  ? Text(
                      _preview(widget.code),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE6F1EA),
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    )
                  : const Text(
                      '代码已折叠，点击展开查看。',
                      style: TextStyle(
                        color: Color(0xFFE6F1EA),
                        fontFamily: 'monospace',
                        height: 1.35,
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

class AttachmentBlock extends StatelessWidget {
  const AttachmentBlock({
    required this.icon,
    required this.title,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return StructuredBlock(icon: icon, title: title, body: detail);
  }
}

class StructuredBlock extends StatelessWidget {
  const StructuredBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.initiallyExpanded = true,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool initiallyExpanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && !initiallyExpanded) {
      return _ExpandableStructuredBlock(
        icon: icon,
        title: title,
        body: body,
        initiallyExpanded: initiallyExpanded,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7DED2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(body),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableStructuredBlock extends StatefulWidget {
  const _ExpandableStructuredBlock({
    required this.icon,
    required this.title,
    required this.body,
    required this.initiallyExpanded,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool initiallyExpanded;

  @override
  State<_ExpandableStructuredBlock> createState() =>
      _ExpandableStructuredBlockState();
}

class _ExpandableStructuredBlockState
    extends State<_ExpandableStructuredBlock> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final preview = widget.body.length > 120
        ? '${widget.body.substring(0, 120)}...'
        : widget.body;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7DED2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(_expanded ? widget.body : preview),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
