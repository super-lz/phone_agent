import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

export 'code_block_card.dart';

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

class WebAppArtifactCard extends StatelessWidget {
  const WebAppArtifactCard({
    required this.title,
    required this.artifactId,
    required this.onTap,
    super.key,
  });

  final String title;
  final String artifactId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.cardSelectedBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.web_asset, color: colors.primaryAction),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '本地应用 · 点击预览',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final colors = context.phoneAgentColors;
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
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: colors.primaryAction),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(body, style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colors.textTertiary,
                  ),
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
    final colors = context.phoneAgentColors;
    final preview = widget.body.length > 120
        ? '${widget.body.substring(0, 120)}...'
        : widget.body;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, size: 18, color: colors.primaryAction),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _expanded ? widget.body : preview,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
