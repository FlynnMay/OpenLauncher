import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// The style's fill as a colour or a gradient.
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

/// Corner radii from [style], or [usual] for all.
BorderRadius styleShape(BoxStyle style, double usual) =>
    switch (style.corners) {
      [final topLeft, final topRight, final bottomRight, final bottomLeft] =>
        BorderRadius.only(
          topLeft: Radius.circular(topLeft),
          topRight: Radius.circular(topRight),
          bottomRight: Radius.circular(bottomRight),
          bottomLeft: Radius.circular(bottomLeft),
        ),
      _ => BorderRadius.circular(usual),
    };

List<BoxShadow>? styleShadow(BoxStyle style) => style.shadow == 0
    ? null
    : [
        BoxShadow(
          color: Colors.black54,
          blurRadius: style.shadow,
          offset: Offset(0, style.shadow / 3),
        ),
      ];

Widget styleOpacity(BoxStyle style, Widget child) =>
    style.opacity == 1 ? child : Opacity(opacity: style.opacity, child: child);

/// The inherited style for the widgets below: text colour, size and the like.
class StyleScope extends InheritedWidget {
  const StyleScope({super.key, required this.values, required super.child});

  final Style values;

  static Style of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StyleScope>()?.values ??
      const {};

  /// [child] with [style]'s inherited properties added to the scope.
  static Widget under(BuildContext context, Style style, Widget child) {
    final own = inheritedOf(style);
    return own.isEmpty
        ? child
        : StyleScope(values: {...of(context), ...own}, child: child);
  }

  @override
  bool updateShouldNotify(StyleScope oldWidget) =>
      !mapEquals(values, oldWidget.values);
}

/// Paints [style] behind [child]. An empty style adds nothing.
class StyledBox extends StatelessWidget {
  const StyledBox({
    super.key,
    required this.style,
    required this.child,
    this.radius = 10,
    this.padding = 8,
  });

  final BoxStyle style;
  final Widget child;

  /// Defaults when [style] sets none.
  final double radius, padding;

  @override
  Widget build(BuildContext context) {
    if (style.isEmpty && style.padding == null) {
      return styleOpacity(style, child);
    }
    final fill = styleFill(style);
    return styleOpacity(
      style,
      DecoratedBox(
        decoration: BoxDecoration(
          color: fill.color,
          gradient: fill.gradient,
          borderRadius: styleShape(style, radius),
          boxShadow: styleShadow(style),
          border: switch (style.border) {
            null => null,
            final border => Border.all(
              color: Color(border),
              width: style.borderWidth,
            ),
          },
        ),
        child: Padding(
          padding: EdgeInsets.all(style.padding ?? padding),
          child: child,
        ),
      ),
    );
  }
}
