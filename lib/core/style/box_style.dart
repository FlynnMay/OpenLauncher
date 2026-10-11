import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/style/style.dart';

/// A [Style] resolved for painting a box: fill, border, corners, padding,
/// opacity, shadow.
@immutable
class BoxStyle {
  const BoxStyle({
    this.colors = const [],
    this.stops = const [],
    this.angle = 180,
    this.border,
    this.borderWidth = 2,
    this.corners,
    this.padding,
    this.opacity = 1,
    this.shadow = 0,
  });

  static const none = BoxStyle();
  static const maxColors = 8;

  /// Fill colours as 0xAARRGGBB: none, one (flat) or several (gradient).
  final List<int> colors;

  /// Gradient stop positions, 0 to 1. Empty spreads them evenly.
  final List<double> stops;

  /// [stops], or even ones when unset.
  List<double> get positions => stops.length == colors.length
      ? stops
      : [
          for (var i = 0; i < colors.length; i++)
            colors.length < 2 ? 0 : i / (colors.length - 1),
        ];

  /// Gradient angle in CSS degrees: 0 up, 90 right.
  final int angle;

  /// Border colour as 0xAARRGGBB, or null for none.
  final int? border;
  final double borderWidth;

  /// Corner radii in TV pixels: top left, top right, bottom right, bottom
  /// left. Null for the default.
  final List<double>? corners;

  /// Null for the default.
  final double? padding;

  /// 0 to 1.
  final double opacity;

  /// Shadow blur; 0 for none.
  final double shadow;

  /// Whether nothing is painted.
  bool get isEmpty => colors.isEmpty && border == null && shadow == 0;

  /// Parses `#RRGGBB` or `#RRGGBBAA`.
  static int? parseColor(Object? css) {
    if (css is! String ||
        !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(css)) {
      return null;
    }
    final rgb = int.parse(css.substring(1, 7), radix: 16);
    final alpha = css.length == 9
        ? int.parse(css.substring(7), radix: 16)
        : 255;
    return alpha << 24 | rgb;
  }

  static String colorToCss(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
      '${(argb >>> 24).toRadixString(16).padLeft(2, '0')}';

  /// A number, or text that parses as one, clamped.
  static double? number(Object? value, [num low = 0, num high = 1000]) {
    final number = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text.trim()),
      _ => null,
    };
    return number == null || !number.isFinite
        ? null
        : number.clamp(low, high).toDouble();
  }

  /// Ignores what it cannot read. Never throws.
  factory BoxStyle.of(Style style) {
    final background = style['background'];
    final colors = background is Map ? background['colors'] : null;
    final stops = background is Map ? background['stops'] : null;
    final angle = background is Map ? background['angle'] : null;
    final read = [
      ?parseColor(background),
      if (colors is List)
        for (final color in colors.take(maxColors)) ?parseColor(color),
    ];
    // Keep stops only if there is one per colour, in range and ascending.
    var last = 0.0;
    final fits =
        stops is List &&
        read.length > 1 &&
        stops.length == read.length &&
        (colors as List).length == read.length &&
        stops.every((stop) {
          if (stop is! num || !(stop >= last && stop <= 1)) return false;
          last = stop * 1.0;
          return true;
        });
    return BoxStyle(
      colors: read,
      stops: fits ? [for (final stop in stops) (stop as num) * 1.0] : const [],
      angle: angle is num && angle.isFinite ? angle.round() % 360 : 180,
      border: parseColor(style['borderColor']),
      borderWidth: number(style['borderWidth'], 0, 20) ?? 2,
      corners: switch (style['radius']) {
        final List<Object?> each when each.length == 4 => [
          for (final corner in each) number(corner, 0, 120) ?? 0,
        ],
        final all => switch (number(all, 0, 120)) {
          null => null,
          final all => List.filled(4, all),
        },
      },
      padding: number(style['padding'], 0, 80),
      opacity: (number(style['opacity'], 0, 100) ?? 100) / 100,
      shadow: number(style['shadow'], 0, 60) ?? 0,
    );
  }

  /// The saved form of a fill: null, one colour, or a gradient map.
  static Object? backgroundOf(
    List<int> colors, [
    List<double> stops = const [],
    int angle = 180,
  ]) => switch (colors) {
    [] => null,
    [final only] => colorToCss(only),
    _ => {
      'colors': colors.map(colorToCss).toList(),
      if (stops.length == colors.length) 'stops': stops,
      'angle': angle,
    },
  };
}
