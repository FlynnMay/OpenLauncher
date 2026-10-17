import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/features/modules/visual_look.dart';

/// How far a number is between two others, as a bar or a ring.
///
/// Values: `value` (a template that reads as a number), `min` (0), `max`
/// (100), `shape` (`bar` or `ring`). Look: `color`.
class MeterVisual extends ConsumerWidget {
  const MeterVisual({super.key, required this.values});

  /// Its module's values, with its style under `style`.
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double number(Object? option, double otherwise) => switch (option) {
      final num number => number.toDouble(),
      _ => otherwise,
    };
    final value = double.tryParse(
      visualText(context, ref, values['value']).trim(),
    );
    final min = number(values['min'], 0), max = number(values['max'], 100);
    final part = value == null || max <= min
        ? 0.0
        : ((value - min) / (max - min)).clamp(0.0, 1.0);
    final colour = cssColour(visualStyle(context, ref, values)['color']);
    return SizedBox.expand(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: part),
        duration: const Duration(milliseconds: 300),
        builder: (context, part, _) => CustomPaint(
          painter: _MeterPainter(
            part: part,
            ring: values['shape'] == 'ring',
            colour: colour,
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({
    required this.part,
    required this.ring,
    required this.colour,
  });

  final double part;
  final bool ring;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = colour.withValues(alpha: colour.a * 0.2);
    final fill = Paint()..color = colour;
    if (!ring) {
      final height = math.min(size.height, 10.0);
      final bar = Rect.fromLTWH(
        0,
        (size.height - height) / 2,
        size.width,
        height,
      );
      final radius = Radius.circular(height / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, radius), track);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * part, height),
          radius,
        ),
        fill,
      );
      return;
    }
    final width = math.max(3.0, size.shortestSide * 0.1);
    final circle = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - width) / 2,
    );
    for (final paint in [track, fill]) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
    }
    canvas.drawArc(circle, 0, 2 * math.pi, false, track);
    // From the top, clockwise.
    canvas.drawArc(circle, -math.pi / 2, 2 * math.pi * part, false, fill);
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.part != part || old.ring != ring || old.colour != colour;
}
