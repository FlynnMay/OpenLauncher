import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';

/// Where a node sits in its parent: each edge is anchored at a fraction of
/// the parent's box, then moved by an offset in TV pixels. Anchors apart on
/// an axis stretch it with the parent; together they pin it at one size.
/// A parent with a Layout places its children itself, so it ignores this.
@immutable
class NodeTransform {
  const NodeTransform({
    this.minX = 0,
    this.minY = 0,
    this.maxX = 1,
    this.maxY = 1,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// Pinned to the top left corner, covering [rect].
  NodeTransform.at(Rect rect)
    : minX = 0,
      minY = 0,
      maxX = 0,
      maxY = 0,
      left = rect.left,
      top = rect.top,
      right = rect.right,
      bottom = rect.bottom;

  /// Fills the parent.
  static const fill = NodeTransform();

  /// Anchors, as fractions of the parent's width and height.
  final double minX, minY, maxX, maxY;

  /// Offsets of the left, top, right and bottom edges from their anchors.
  final double left, top, right, bottom;

  bool get isFill => this == fill;

  /// Its box in a parent of [size].
  Rect rectIn(Size size) => Rect.fromLTRB(
    minX * size.width + left,
    minY * size.height + top,
    maxX * size.width + right,
    maxY * size.height + bottom,
  );

  /// The same anchors, offset to cover [rect] in a parent of [size].
  NodeTransform covering(Rect rect, Size size) => NodeTransform(
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
    left: rect.left - minX * size.width,
    top: rect.top - minY * size.height,
    right: rect.right - maxX * size.width,
    bottom: rect.bottom - maxY * size.height,
  );

  static NodeTransform fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) return fill;
    List<double>? four(String key) => switch (json[key]) {
      [final num a, final num b, final num c, final num d] => [
        for (final value in [a, b, c, d]) value.toDouble(),
      ],
      _ => null,
    };
    final anchors = four('anchors') ?? const [0.0, 0.0, 1.0, 1.0];
    final offsets = four('offsets') ?? const [0.0, 0.0, 0.0, 0.0];
    return NodeTransform(
      minX: anchors[0],
      minY: anchors[1],
      maxX: anchors[2],
      maxY: anchors[3],
      left: offsets[0],
      top: offsets[1],
      right: offsets[2],
      bottom: offsets[3],
    );
  }

  Map<String, Object?> toJson() => {
    if (minX != 0 || minY != 0 || maxX != 1 || maxY != 1)
      'anchors': [
        for (final value in [minX, minY, maxX, maxY]) tidy(value),
      ],
    if (left != 0 || top != 0 || right != 0 || bottom != 0)
      'offsets': [
        for (final value in [left, top, right, bottom]) tidy(value),
      ],
  };

  @override
  bool operator ==(Object other) =>
      other is NodeTransform &&
      other.minX == minX &&
      other.minY == minY &&
      other.maxX == maxX &&
      other.maxY == maxY &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode =>
      Object.hash(minX, minY, maxX, maxY, left, top, right, bottom);
}
