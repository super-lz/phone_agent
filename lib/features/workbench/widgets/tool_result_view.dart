import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/capabilities/capability_result_presentation.dart';
import '../../maps/amap_location_page.dart';

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
    final presentation = presentCapabilityResult(
      capabilityId: capabilityId,
      output: output,
    );
    return _GenericToolResultCard(
      presentation: presentation,
      capabilityId: capabilityId,
      output: output,
    );
  }
}

class _GenericToolResultCard extends StatefulWidget {
  const _GenericToolResultCard({
    required this.presentation,
    required this.capabilityId,
    required this.output,
  });

  final CapabilityResultPresentation presentation;
  final String capabilityId;
  final Map<String, Object?> output;

  @override
  State<_GenericToolResultCard> createState() => _GenericToolResultCardState();
}

class _GenericToolResultCardState extends State<_GenericToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final colors = context.phoneAgentColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: presentation.ok
            ? colors.cardSelectedBackground
            : colors.warningBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    presentation.ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 18,
                    color: presentation.ok
                        ? colors.primaryAction
                        : const Color(0xFFE0523D),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      presentation.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  _StatusPill(ok: presentation.ok),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                presentation.summary,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              if (widget.capabilityId == 'location.get_current' &&
                  presentation.ok)
                _LocationMapAction(output: widget.output),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Text(
                  '调试详情 · ${widget.capabilityId}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  presentation.detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationMapAction extends StatelessWidget {
  const _LocationMapAction({required this.output});

  final Map<String, Object?> output;

  @override
  Widget build(BuildContext context) {
    final latitude = _doubleValue(output['latitude']);
    final longitude = _doubleValue(output['longitude']);
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.map_outlined, size: 18),
        label: const Text('查看地图'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AmapLocationPage(
                latitude: latitude,
                longitude: longitude,
                accuracy: _doubleValue(output['accuracy']),
                title: output['isCurrent'] == false ? '系统上次定位' : '当前位置',
                subtitle: _locationSubtitle(output),
              ),
            ),
          );
        },
      ),
    );
  }

  String _locationSubtitle(Map<String, Object?> output) {
    final address = output['address'];
    if (address is String && address.trim().isNotEmpty) {
      return address.trim();
    }
    final latitude = _doubleValue(output['latitude']);
    final longitude = _doubleValue(output['longitude']);
    if (latitude == null || longitude == null) {
      return '坐标不可用';
    }
    return '纬度 ${latitude.toStringAsFixed(6)}，经度 ${longitude.toStringAsFixed(6)}';
  }

  double? _doubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

class _WebToolResultCard extends StatefulWidget {
  const _WebToolResultCard({required this.capabilityId, required this.output});

  final String capabilityId;
  final Map<String, Object?> output;

  @override
  State<_WebToolResultCard> createState() => _WebToolResultCardState();
}

class _WebToolResultCardState extends State<_WebToolResultCard> {
  bool _expanded = false;

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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ok ? colors.cardSelectedBackground : colors.warningBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  _StatusPill(ok: ok),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textTertiary,
                  ),
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
      ),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ok ? colors.cardBackground : colors.warningBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          ok ? 'OK' : 'ERR',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ok ? colors.statusText : const Color(0xFFE0523D),
          ),
        ),
      ),
    );
  }
}
