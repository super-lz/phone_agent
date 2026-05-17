import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ToolResultView extends StatelessWidget {
  const ToolResultView({
    required this.capabilityId,
    required this.output,
    super.key,
  });

  final String capabilityId;
  final Map<String, Object?> output;

  @override
  Widget build(BuildContext context) {
    if (capabilityId == 'web.search' || capabilityId == 'web.fetch') {
      return _WebToolResultCard(capabilityId: capabilityId, output: output);
    }
    return _StructuredResultCard(
      icon: Icons.check_circle_outline,
      title: 'Tool Result · $capabilityId',
      body: output.toString(),
    );
  }
}

class _WebToolResultCard extends StatelessWidget {
  const _WebToolResultCard({required this.capabilityId, required this.output});

  final String capabilityId;
  final Map<String, Object?> output;

  @override
  Widget build(BuildContext context) {
    final ok = output['ok'] == true;
    final content = output['content'];
    final error = output['error'];
    final provider = output['provider'];
    final url = output['url'];
    final query = output['query'];
    final title = capabilityId == 'web.fetch' ? '网页解析结果' : '联网搜索结果';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFF1F6F2) : const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok ? const Color(0xFFD2E2D7) : const Color(0xFFF0C8C0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.public : Icons.error_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              _StatusPill(ok: ok),
            ],
          ),
          const SizedBox(height: 8),
          if (provider is String && provider.isNotEmpty)
            _MetaLine(label: 'Provider', value: provider),
          if (query is String && query.isNotEmpty)
            _MetaLine(label: 'Query', value: query),
          if (url is String && url.isNotEmpty)
            _MetaLine(label: 'URL', value: url),
          if (error is String && error.isNotEmpty)
            _ErrorText(error: error)
          else if (content is String && content.isNotEmpty)
            _SearchContent(content: content)
          else
            const Text('工具没有返回可展示内容。'),
        ],
      ),
    );
  }
}

class _SearchContent extends StatelessWidget {
  const _SearchContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
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
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Text(error, style: const TextStyle(color: Color(0xFF9A3412)));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFDFF3E6) : const Color(0xFFFFDED8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          ok ? 'OK' : 'ERR',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _StructuredResultCard extends StatelessWidget {
  const _StructuredResultCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4EF),
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
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
