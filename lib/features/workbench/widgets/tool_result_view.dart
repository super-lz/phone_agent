import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';
import '../../../application/capabilities/capability_result_presentation.dart';
import '../../maps/amap_location_page.dart';
import 'tool_result_status.dart';
import 'web_tool_result_card.dart';

class ToolResultView extends StatelessWidget {
  const ToolResultView({
    required this.capabilityId,
    required this.output,
    this.showFrame = true,
    super.key,
  });

  final String capabilityId;
  final Map<String, Object?> output;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    if (capabilityId == 'web.search' || capabilityId == 'web.fetch') {
      return WebToolResultCard(
        capabilityId: capabilityId,
        output: output,
        showFrame: showFrame,
      );
    }
    final presentation = presentCapabilityResult(
      capabilityId: capabilityId,
      output: output,
    );
    return _GenericToolResultCard(
      presentation: presentation,
      capabilityId: capabilityId,
      output: output,
      showFrame: showFrame,
    );
  }
}

class _GenericToolResultCard extends StatefulWidget {
  const _GenericToolResultCard({
    required this.presentation,
    required this.capabilityId,
    required this.output,
    this.showFrame = true,
  });

  final CapabilityResultPresentation presentation;
  final String capabilityId;
  final Map<String, Object?> output;
  final bool showFrame;

  @override
  State<_GenericToolResultCard> createState() => _GenericToolResultCardState();
}

class _GenericToolResultCardState extends State<_GenericToolResultCard> {
  late bool _expanded = !widget.presentation.ok;

  @override
  void didUpdateWidget(_GenericToolResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentation.ok != widget.presentation.ok) {
      _expanded = !widget.presentation.ok;
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final colors = context.phoneAgentColors;
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
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                ToolResultStatus(ok: presentation.ok),
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
              SelectionArea(
                child: Text(
                  presentation.detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ],
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
        color: presentation.ok
            ? colors.cardSelectedBackground
            : colors.warningBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: body,
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
