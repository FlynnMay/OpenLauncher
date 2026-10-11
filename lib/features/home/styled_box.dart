import 'dart:math';

import 'package:flutter/foundation.dart';
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

/// The outline of a box: each corner as round as [style] says, or all of
/// them as round as boxes of its sort [usual]ly are.
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

/// The shadow [style] asks for, if it does.
List<BoxShadow>? styleShadow(BoxStyle style) => style.shadow == 0
    ? null
    : [
        BoxShadow(
          color: Colors.black54,
          blurRadius: style.shadow,
          offset: Offset(0, style.shadow / 3),
        ),
      ];

/// [child] as solid as [style] says.
Widget styleOpacity(BoxStyle style, Widget child) =>
    style.opacity == 1 ? child : Opacity(opacity: style.opacity, child: child);

/// What of the looks around them the things under it take after: the
/// colour and size of letters, and the like. A pane hands its own down to
/// everything in it, an instance of a prefab to its parts.
class StyleScope extends InheritedWidget {
  const StyleScope({super.key, required this.values, required super.child});

  final Style values;

  /// What is handed down to [context]: nothing where nothing set any.
  static Style of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StyleScope>()?.values ??
      const {};

  /// [child] with what of [style] is taken after handed down to it, on top
  /// of what [context] was handed itself.
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

/// Paints the user's [style] behind [child], with room around it. An empty
/// style adds nothing at all.
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

  /// How round its corners are, and the room it keeps, where [style] does
  /// not say.
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
