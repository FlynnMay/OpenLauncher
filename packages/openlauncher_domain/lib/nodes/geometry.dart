import 'package:meta/meta.dart';

/// A width and a height, in TV pixels.
@immutable
class Extent {
  const Extent(this.width, this.height);

  final double width, height;

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

  final double left, top, right, bottom;

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
