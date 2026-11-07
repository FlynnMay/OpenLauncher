import 'package:meta/meta.dart';

/// A width and a height, in TV pixels.
@immutable
class Extent {
  const Extent(this.width, this.height);

  /// Reads `[width, height]`; null if [json] is not that.
  static Extent? fromJson(Object? json) => switch (json) {
    [final num width, final num height] => Extent(
      width.toDouble(),
      height.toDouble(),
    ),
    _ => null,
  };

  final double width, height;

  List<double> toJson() => [width, height];

  @override
  bool operator ==(Object other) =>
      other is Extent && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Extent($width, $height)';
}

/// A rectangle, by its four edges, in TV pixels.
@immutable
class Box {
  const Box.fromLTRB(this.left, this.top, this.right, this.bottom);

  const Box.fromLTWH(double left, double top, double width, double height)
    : this.fromLTRB(left, top, left + width, top + height);

  /// Reads `[left, top, right, bottom]`; null if [json] is not that.
  static Box? fromJson(Object? json) => switch (json) {
    [final num left, final num top, final num right, final num bottom] =>
      Box.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      ),
    _ => null,
  };

  final double left, top, right, bottom;

  List<double> toJson() => [left, top, right, bottom];

  double get width => right - left;
  double get height => bottom - top;
  Extent get extent => Extent(width, height);

  @override
  bool operator ==(Object other) =>
      other is Box &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Box($left, $top, $right, $bottom)';
}
