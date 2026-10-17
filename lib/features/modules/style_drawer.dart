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

/// Corner radii from [style], or [fallback] for all.
BorderRadius styleShape(BoxStyle style, double fallback) =>
    switch (style.corners) {
      [final topLeft, final topRight, final bottomRight, final bottomLeft] =>
        BorderRadius.only(
          topLeft: Radius.circular(topLeft),
          topRight: Radius.circular(topRight),
          bottomRight: Radius.circular(bottomRight),
          bottomLeft: Radius.circular(bottomLeft),
        ),
      _ => BorderRadius.circular(fallback),
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

/// What a box takes where its style sets nothing.
@immutable
class BoxDefaults {
  const BoxDefaults({
    this.padding = 8,
    this.corner = 10,
    this.padsBare = false,
    this.clips = false,
  });

  final double padding, corner;

  /// Padded even when it paints nothing.
  final bool padsBare;

  /// What is in it is cut off at the box.
  final bool clips;

  /// Padding inside [box].
  double paddingOf(BoxStyle box) =>
      box.padding ?? (padsBare || !box.isEmpty ? padding : 0);
}

/// How far a focused child may show past a box that cuts off what is in it
/// but paints nothing.
const overhang = 12.0;

/// Clips [by] outside the box.
class Inflated extends CustomClipper<Rect> {
  const Inflated(this.by);

  final double by;

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(by);

  @override
  bool shouldReclip(Inflated oldClipper) => oldClipper.by != by;
}

/// Paints a node's Style around [child]: fill and shadow behind, border over
/// it, taking no space. Padding and opacity are applied by the node.
class NodeBox extends StatelessWidget {
  const NodeBox({
    super.key,
    required this.box,
    required this.defaults,
    required this.child,
  });

  final BoxStyle box;
  final BoxDefaults defaults;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (box.isEmpty) {
      return defaults.clips
          ? ClipRect(clipper: const Inflated(overhang), child: child)
          : child;
    }
    final fill = styleFill(box);
    final shape = styleShape(box, defaults.corner);
    final border = box.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill.color,
        gradient: fill.gradient,
        borderRadius: shape,
        boxShadow: styleShadow(box),
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: border == null
              ? null
              : Border.all(color: Color(border), width: box.borderWidth),
        ),
        child: defaults.clips
            ? ClipRRect(borderRadius: shape, child: child)
            : child,
      ),
    );
  }
}
