import 'package:flutter/foundation.dart';

/// How the box behind a section or a card is painted: nothing, one colour,
/// or a gradient, each colour with its own transparency, and optionally an
/// outline. Chosen on the config page.
@immutable
class BoxStyle {
  const BoxStyle({
    this.colors = const [],
    this.stops = const [],
    this.angle = 180,
    this.border,
  });

  static const none = BoxStyle();
  static const maxColors = 8;

  /// Fill colours as 0xAARRGGBB. None leaves the box as it normally is, one
  /// is a flat colour, more make a gradient.
  final List<int> colors;

  /// Where along a gradient each colour is at its fullest, 0 at the start
  /// to 1 at the end, in order. Empty spreads the colours evenly.
  final List<double> stops;

  /// [stops], worked out when they are left to be even.
  List<double> get positions => stops.length == colors.length
      ? stops
      : [
          for (var i = 0; i < colors.length; i++)
            colors.length < 2 ? 0 : i / (colors.length - 1),
        ];

  /// Direction of a gradient in degrees, as CSS counts them: 0 runs
  /// upwards, 90 to the right, 180 downwards.
  final int angle;

  /// Outline colour as 0xAARRGGBB, or null for none.
  final int? border;

  bool get isEmpty => colors.isEmpty && border == null;

  /// Reads `#RRGGBB` or `#RRGGBBAA`, the forms CSS and the page use.
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

  /// Never throws: a style is decoration, so whatever is not understood is
  /// simply left out.
  factory BoxStyle.fromJson(Object? json) {
    if (json is! Map) return none;
    final colors = json['colors'], angle = json['angle'];
    final stops = json['stops'];
    final read = [
      if (colors is List)
        for (final color in colors.take(maxColors)) ?parseColor(color),
    ];
    // Only stops that fit the colours are kept: one each, none out of
    // range or before the one in front of it.
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
      border: parseColor(json['border']),
    );
  }

  Map<String, Object?> toJson() => {
    if (colors.isNotEmpty) 'colors': colors.map(colorToCss).toList(),
    if (colors.length > 1 && stops.length == colors.length) 'stops': stops,
    if (colors.length > 1) 'angle': angle,
    'border': ?switch (border) {
      null => null,
      final border => colorToCss(border),
    },
  };
}
