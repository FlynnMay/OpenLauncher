import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/style/style.dart';

/// How a box is painted, read from the [Style] of whatever the box is:
/// its fill (nothing, one colour, or a gradient), its outline, how round
/// its corners are, the room it keeps inside, and how solid it is.
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

  /// Outline colour as 0xAARRGGBB, or null for none, and how thick it is.
  final int? border;
  final double borderWidth;

  /// How round each corner is, in the TV's 960-wide pixels: top left, top
  /// right, bottom right, bottom left. Null for the usual of what it is.
  final List<double>? corners;

  /// The room between its edge and what is in it; null for the usual.
  final double? padding;

  /// From 0, not there, to 1, solid.
  final double opacity;

  /// How far its shadow spreads; 0 for none.
  final double shadow;

  /// Whether nothing of it is painted.
  bool get isEmpty => colors.isEmpty && border == null && shadow == 0;

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

  /// A measure as a look may say it: a number, or one as text, which is
  /// what a template reads as.
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

  /// Never throws: whatever of [style] is not understood is left out.
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

  /// A fill as a look says it: nothing for no colour, the colour alone
  /// for one, and for a gradient its colours, where each sits and the way
  /// it runs.
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
