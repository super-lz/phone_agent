import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/phone_agent_colors.dart';
import 'tool_result_status.dart';

class WebToolResultCard extends StatefulWidget {
  const WebToolResultCard({
    required this.capabilityId,
    required this.output,
    this.showFrame = true,
    super.key,
  });

  final String capabilityId;
  final Map<String, Object?> output;
  final bool showFrame;

  @override
  State<WebToolResultCard> createState() => _WebToolResultCardState();
}

class _WebToolResultCardState extends State<WebToolResultCard> {
  late bool _expanded = widget.output['ok'] != true;

  @override
  void didUpdateWidget(WebToolResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOk = oldWidget.output['ok'] == true;
    final newOk = widget.output['ok'] == true;
    if (oldOk != newOk) {
      _expanded = !newOk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.output['ok'] == true;
    final colors = context.phoneAgentColors;
    final content = widget.output['content'];
    final error = widget.output['error'];
    final provider = widget.output['provider'];
    final url = widget.output['url'];
    final query = widget.output['query'];
    final title = widget.capabilityId == 'web.fetch' ? '网页解析结果' : '联网搜索结果';

    final body = InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: widget.showFrame ? BorderRadius.circular(16) : null,
      child: Padding(
        padding: EdgeInsets.all(widget.showFrame ? 10 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.public : Icons.error_outline,
                  size: 18,
                  color: ok ? colors.primaryAction : const Color(0xFFE0523D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                ToolResultStatus(ok: ok),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: colors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (provider is String && provider.isNotEmpty)
              _MetaLine(label: '来源', value: provider),
            if (query is String && query.isNotEmpty)
              _MetaLine(label: '搜索词', value: query),
            if (url is String && url.isNotEmpty)
              _MetaLine(label: '网址', value: url),
            if (error is String && error.isNotEmpty)
              _ErrorText(error: error)
            else if (_expanded && content is String && content.isNotEmpty)
              _SearchContent(content: content)
            else if (!_expanded && content is String && content.isNotEmpty)
              Text(
                _preview(content),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              const Text('工具没有返回可展示内容。'),
          ],
        ),
      ),
    );
    if (!widget.showFrame) {
      return body;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ok ? colors.cardSelectedBackground : colors.warningBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: body,
    );
  }

  String _preview(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '工具返回了空内容。';
    }
    if (normalized.length > 180) {
      return '${normalized.substring(0, 180)}...';
    }
    return normalized;
  }
}

class _SearchContent extends StatelessWidget {
  const _SearchContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    final links = _extractLinks(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(data: content),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('来源链接', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final link in links.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                link,
                style: TextStyle(color: colors.primaryAction),
              ),
            ),
        ],
      ],
    );
  }

  List<String> _extractLinks(String text) {
    final matches = RegExp(r'https?://[^\s\])}>"]+').allMatches(text);
    return matches
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Text(error, style: const TextStyle(color: Color(0xFFE0523D)));
  }
}
