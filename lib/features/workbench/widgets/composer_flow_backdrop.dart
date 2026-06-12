import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/phone_agent_colors.dart';

class ComposerFlowBackdrop extends StatefulWidget {
  const ComposerFlowBackdrop({required this.isSending, super.key});

  final bool isSending;

  @override
  State<ComposerFlowBackdrop> createState() => _ComposerFlowBackdropState();
}

class _ComposerFlowBackdropState extends State<ComposerFlowBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _flowController;
  late final AnimationController _activationController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _activationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      reverseDuration: const Duration(milliseconds: 720),
      value: widget.isSending ? 1 : 0,
    );
    if (widget.isSending) {
      _flowController.repeat();
    }
  }

  @override
  void didUpdateWidget(ComposerFlowBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSending == oldWidget.isSending) {
      return;
    }
    if (widget.isSending) {
      _flowController.repeat();
      _activationController.animateTo(1, curve: Curves.easeInOutCubic);
      return;
    }
    _activationController.animateBack(0, curve: Curves.easeInOutCubic).then((
      _,
    ) {
      if (mounted && !widget.isSending) {
        _flowController
          ..stop()
          ..value = 0;
      }
    });
  }

  @override
  void dispose() {
    _flowController.dispose();
    _activationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.phoneAgentColors;
    return AnimatedBuilder(
      animation: Listenable.merge([_flowController, _activationController]),
      builder: (context, child) {
        return CustomPaint(
          painter: _ComposerFlowBackdropPainter(
            flowValue: _flowController.value,
            activationValue: _activationController.value,
            primaryColor: colors.primaryAction,
          ),
        );
      },
    );
  }
}

class _ComposerFlowBackdropPainter extends CustomPainter {
  const _ComposerFlowBackdropPainter({
    required this.flowValue,
    required this.activationValue,
    required this.primaryColor,
  });

  final double flowValue;
  final double activationValue;
  final Color primaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    if (width <= 0 || height <= 0) {
      return;
    }

    final active = activationValue.clamp(0.0, 1.0);
    if (active <= 0.001) {
      return;
    }

    final field = Rect.fromLTWH(0, 0, width, height);
    final cycle = flowValue * 2 * math.pi;
    final ember = _delayedEase(active, 0, 0.45);
    final flameReveal = _delayedEase(active, 0.04, 0.95);
    final washReveal = _delayedEase(active, 0.24, 1);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-40, 0, width + 40, height));
    _drawBaseGlow(canvas, field, width, ember, flameReveal, cycle);
    _drawSoftWash(canvas, field, width, ember, washReveal, cycle);
    _drawFlameField(canvas, field, width, flameReveal, cycle);
    canvas.restore();
  }

  void _drawBaseGlow(
    Canvas canvas,
    Rect field,
    double width,
    double ember,
    double flameReveal,
    double cycle,
  ) {
    final bedHeight = field.height * (0.38 + flameReveal * 0.16);
    final bedTop = field.bottom - bedHeight;
    final bedAlpha = ember * (0.52 + flameReveal * 0.68);
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          _spectrumColor(0, bedAlpha * 0.16),
          _spectrumColor(5, bedAlpha * 0.11),
          _spectrumColor(10, bedAlpha * 0.045),
          primaryColor.withValues(alpha: 0),
        ],
        stops: const [0, 0.28, 0.62, 1],
      ).createShader(Rect.fromLTRB(0, bedTop, width, field.bottom))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawRect(Rect.fromLTRB(0, bedTop, width, field.bottom), basePaint);

    for (var i = 0; i < 6; i++) {
      final phase = cycle + i * 0.92;
      final center = Offset(
        width * (-0.06 + i * 0.22 + 0.035 * math.sin(phase)),
        field.height * (1.03 - 0.05 * flameReveal),
      );
      final radius = width * (0.24 + (i % 2) * 0.06);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            _spectrumColor(i * 4 + 1, bedAlpha * 0.15),
            _spectrumColor(i * 4 + 3, bedAlpha * 0.075),
            primaryColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawSoftWash(
    Canvas canvas,
    Rect field,
    double width,
    double ember,
    double washReveal,
    double cycle,
  ) {
    for (var i = 0; i < 9; i++) {
      final phase = cycle + i * 0.86;
      final targetY =
          field.height * (0.42 + 0.055 * (i % 6) + 0.035 * math.cos(phase));
      final center = Offset(
        width * (0.08 + i * 0.105 + 0.045 * math.sin(phase)),
        _lerp(field.height * 1.05, targetY, washReveal),
      );
      final radius =
          width * (0.14 + (i % 3) * 0.028) * (0.26 + washReveal * 0.74);
      final alpha = ember * (0.25 + washReveal * 0.75);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            _spectrumColor(i * 3, alpha * 0.075),
            _spectrumColor(i * 3 + 2, alpha * 0.035),
            primaryColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawFlameField(
    Canvas canvas,
    Rect field,
    double width,
    double flameReveal,
    double cycle,
  ) {
    if (flameReveal <= 0.001) {
      return;
    }
    final specs = [
      _FlameSpec(x: -0.02, reach: 0.38, sway: 0.082, phase: 0.1, width: 58),
      _FlameSpec(x: 0.09, reach: 0.51, sway: 0.104, phase: 0.7, width: 72),
      _FlameSpec(x: 0.20, reach: 0.43, sway: 0.088, phase: 1.2, width: 62),
      _FlameSpec(x: 0.32, reach: 0.58, sway: 0.112, phase: 1.9, width: 78),
      _FlameSpec(x: 0.45, reach: 0.47, sway: 0.096, phase: 2.6, width: 66),
      _FlameSpec(x: 0.58, reach: 0.55, sway: 0.108, phase: 3.3, width: 76),
      _FlameSpec(x: 0.71, reach: 0.42, sway: 0.092, phase: 4.0, width: 64),
      _FlameSpec(x: 0.84, reach: 0.52, sway: 0.104, phase: 4.7, width: 74),
      _FlameSpec(x: 0.98, reach: 0.39, sway: 0.086, phase: 5.4, width: 60),
    ];

    for (var i = 0; i < specs.length; i++) {
      _drawFlame(canvas, field, width, flameReveal, cycle, specs[i], i);
    }
  }

  void _drawFlame(
    Canvas canvas,
    Rect field,
    double width,
    double flameReveal,
    double cycle,
    _FlameSpec spec,
    int index,
  ) {
    final path = Path();
    final baseX = width * spec.x;
    final baseY = _lerp(field.height * 1.18, field.height * 0.82, flameReveal);
    final reach = field.height * spec.reach * math.pow(flameReveal, 1.18);
    final stepCount = 9;
    var first = true;

    for (var step = 0; step <= stepCount; step++) {
      final t = step / stepCount;
      final taper = math.pow(1 - t, 0.65).toDouble();
      final drift =
          (math.sin(cycle + spec.phase + t * math.pi * 2.2) *
                  width *
                  spec.sway +
              math.sin(cycle * 2 - spec.phase + t * math.pi * 4.4) *
                  width *
                  spec.sway *
                  0.34) *
          taper;
      final flutter =
          math.sin(cycle * 3 + spec.phase * 0.7 + t * math.pi * 3.2) *
          field.height *
          0.015 *
          (1 - taper);
      final x = baseX + drift;
      final y = baseY - reach * t + flutter;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          _spectrumColor(index * 2, flameReveal * 0.18),
          _spectrumColor(index * 2 + 1, flameReveal * 0.15),
          _spectrumColor(index * 2 + 4, flameReveal * 0.09),
          _spectrumColor(index * 2 + 7, flameReveal * 0.035),
          _spectrumColor(index * 2 + 10, 0),
        ],
        stops: const [0, 0.22, 0.50, 0.76, 1],
      ).createShader(field)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, spec.width * 0.34);

    canvas.drawPath(path, paint);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.width * 0.34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          _spectrumColor(index * 2 + 3, flameReveal * 0.13),
          _spectrumColor(index * 2 + 8, flameReveal * 0.045),
          _spectrumColor(index * 2 + 12, 0),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(field)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, spec.width * 0.18);

    canvas.drawPath(path, highlightPaint);
  }

  Color _spectrumColor(int index, double alpha) {
    final hue = (flowValue * 360 + index * 29) % 360;
    return HSVColor.fromAHSV(alpha.clamp(0.0, 1.0), hue, 0.72, 1).toColor();
  }

  double _easeInOut(double value) {
    final t = value.clamp(0.0, 1.0);
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  double _delayedEase(double value, double start, double end) {
    if (value <= start) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return _easeInOut((value - start) / (end - start));
  }

  double _lerp(double from, double to, double t) {
    return from + (to - from) * t.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _ComposerFlowBackdropPainter oldDelegate) {
    return oldDelegate.flowValue != flowValue ||
        oldDelegate.activationValue != activationValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}

class _FlameSpec {
  const _FlameSpec({
    required this.x,
    required this.reach,
    required this.sway,
    required this.phase,
    required this.width,
  });

  final double x;
  final double reach;
  final double sway;
  final double phase;
  final double width;
}
