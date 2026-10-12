import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/style/box_style.dart';
import 'package:openlauncher/core/style/style.dart';

/// A [Style]'s scroll bar properties resolved for painting.
@immutable
class ScrollbarStyle {
  const ScrollbarStyle({
    this.thumb = BoxStyle.none,
    this.track = BoxStyle.none,
    this.start = false,
    this.size = 6,
    this.length = 1,
    this.margin = 4,
    this.endMargin = 4,
    this.inset = 0,
    this.minLength = 24,
    this.opacity = 1,
  });

  /// The part that moves, or of a progress bar the part that fills. Only
  /// fill, border and corners are used.
  final BoxStyle thumb;

  /// What it moves along.
  final BoxStyle track;

  /// On the left or top edge instead of the right or bottom.
  final bool start;

  /// Thickness of the track.
  final double size;

  /// Share of the edge the track covers, 0 to 1, centred.
  final double length;

  /// Gap to the edge it is on, and to the ends of that edge.
  final double margin, endMargin;

  /// Gap between the track's sides and the thumb.
  final double inset;

  /// Shortest a thumb gets.
  final double minLength;

  /// 0 to 1.
  final double opacity;

  /// Ignores what it cannot read. Never throws.
  factory ScrollbarStyle.of(Style style) {
    BoxStyle part(String name) => BoxStyle.of({
      'background': style[name],
      'borderColor': style['${name}Border'],
      'borderWidth': style['${name}BorderWidth'] ?? 1,
      'radius': style['${name}Radius'],
    });
    final size = BoxStyle.number(style['scrollbarSize'], 1, 40) ?? 6;
    return ScrollbarStyle(
      thumb: part('scrollbarThumb'),
      track: part('scrollbarTrack'),
      start: style['scrollbarSide'] == 'start',
      size: size,
      length: (BoxStyle.number(style['scrollbarLength'], 5, 100) ?? 100) / 100,
      margin: BoxStyle.number(style['scrollbarMargin'], 0, 80) ?? 4,
      endMargin: BoxStyle.number(style['scrollbarEndMargin'], 0, 200) ?? 4,
      // Leaves some thumb.
      inset: (BoxStyle.number(style['scrollbarInset'], 0, 20) ?? 0).clamp(
        0,
        (size - 1) / 2,
      ),
      minLength: BoxStyle.number(style['scrollbarMinLength'], 4, 400) ?? 24,
      opacity:
          (BoxStyle.number(style['scrollbarOpacity'], 0, 100) ?? 100) / 100,
    );
  }
}
