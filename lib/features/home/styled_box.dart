import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// The fill the user chose, as a colour or a gradient; both null if none.
({Color? color, Gradient? gradient}) styleFill(BoxStyle style) {
  final colors = [for (final color in style.colors) Color(color)];
  if (colors.length < 2) return (color: colors.firstOrNull, gradient: null);
  // CSS angles: 0 points up and they grow clockwise.
  final radians = style.angle * pi / 180;
  final towards = Alignment(sin(radians), -cos(radians));
  return (
    color: null,
    gradient: LinearGradient(
      begin: -towards,
      end: towards,
      colors: colors,
      stops: style.positions,
    ),
  );
}

/// Paints the user's [style] behind [child], with room around it. An empty
/// style adds nothing at all.
class StyledBox extends StatelessWidget {
  const StyledBox({
    super.key,
    required this.style,
    required this.child,
    this.radius = 14,
    this.padding = const EdgeInsets.all(16),
  });

  final BoxStyle style;
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (style.isEmpty) return child;
    final fill = styleFill(style);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill.color,
        gradient: fill.gradient,
        borderRadius: BorderRadius.circular(radius),
        border: switch (style.border) {
          null => null,
          final border => Border.all(color: Color(border), width: 2),
        },
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
