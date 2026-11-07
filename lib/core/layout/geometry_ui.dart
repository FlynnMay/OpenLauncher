import 'dart:ui';

import 'package:openlauncher_domain/nodes/nodes.dart';

/// The domain's plain geometry in Flutter's types, for drawing.
extension BoxRect on Box {
  Rect get rect => Rect.fromLTRB(left, top, right, bottom);
}

extension ExtentSize on Extent {
  Size get size => Size(width, height);
}

extension RectBox on Rect {
  Box get box => Box.fromLTRB(left, top, right, bottom);
}

extension SizeExtent on Size {
  Extent get extent => Extent(width, height);
}

extension NodeTransformRect on NodeTransform {
  /// Its box in a parent of [size].
  Rect rectIn(Size size) => boxIn(size.extent).rect;

  /// The same anchors, offset to cover [rect] in a parent of [size].
  NodeTransform covering(Rect rect, Size size) =>
      coveringBox(rect.box, size.extent);
}

/// A transform pinned to the top left corner, covering [rect].
NodeTransform transformAt(Rect rect) => NodeTransform.atBox(rect.box);
