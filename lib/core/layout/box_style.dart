import 'package:flutter/foundation.dart';

/// How the box behind a section or a card is painted: nothing, one colour,
/// or a gradient, each colour with its own transparency, and optionally an
/// outline. Chosen on the config page.
@immutable
class BoxStyle {
  const BoxStyle({this.colors = const [], this.angle = 180, this.border});

  static const none = BoxStyle();
  static const maxColors = 4;

  /// Fill colours as 0xAARRGGBB. None leaves the box as it normally is, one
  /// is a flat colour, more make a gradient.
  final List<int> colors;

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
    return BoxStyle(
      colors: [
        if (colors is List)
          for (final color in colors.take(maxColors)) ?parseColor(color),
      ],
      angle: angle is num && angle.isFinite ? angle.round() % 360 : 180,
      border: parseColor(json['border']),
    );
  }

  Map<String, Object?> toJson() => {
    if (colors.isNotEmpty) 'colors': colors.map(colorToCss).toList(),
    if (colors.length > 1) 'angle': angle,
    'border': ?switch (border) {
      null => null,
      final border => colorToCss(border),
    },
  };
}
