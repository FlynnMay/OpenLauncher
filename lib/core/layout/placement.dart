import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/layout_model.dart';

/// The cells an item covers: column and row from zero, and its size. Whole
/// numbers except in a [SectionMode.free] section.
@immutable
class Placement {
  const Placement(this.x, this.y, this.w, this.h);

  final double x, y, w, h;

  @override
  bool operator ==(Object other) =>
      other is Placement &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'Placement($x, $y, ${w}x$h)';
}

/// Works out where each of [items] goes on a grid [columns] wide, in the
/// same order as [items].
///
/// In [SectionMode.flow] the items follow one another the way CSS grid
/// auto-placement puts them, so the config page can preview a section with a
/// plain CSS grid. In [SectionMode.grid] items sit where they say; any that
/// have no position, or whose position is taken, fill the first free space.
/// In [SectionMode.free] items are simply where they say, overlapping or
/// not.
List<Placement> placeItems(
  List<LayoutItem> items,
  int columns,
  SectionMode mode,
) {
  if (mode == SectionMode.free) {
    return [
      for (final item in items)
        Placement(item.x ?? 0, item.y ?? 0, min(item.w, columns * 1.0), item.h),
    ];
  }
  final taken = <(int, int)>{};
  bool free(int x, int y, int w, int h) {
    if (x + w > columns) return false;
    for (var row = y; row < y + h; row++) {
      for (var column = x; column < x + w; column++) {
        if (taken.contains((column, row))) return false;
      }
    }
    return true;
  }

  Placement take(int x, int y, int w, int h) {
    for (var row = y; row < y + h; row++) {
      for (var column = x; column < x + w; column++) {
        taken.add((column, row));
      }
    }
    return Placement(x * 1.0, y * 1.0, w * 1.0, h * 1.0);
  }

  final placed = List<Placement?>.filled(items.length, null);
  if (mode == SectionMode.grid) {
    for (final (index, item) in items.indexed) {
      final x = item.x?.round(), y = item.y?.round();
      final w = min(item.w.round(), columns), h = item.h.round();
      if (x != null && y != null && free(x, y, w, h)) {
        placed[index] = take(x, y, w, h);
      }
    }
  }

  // The flow cursor only moves forward, which keeps items in their order.
  var cursorX = 0, cursorY = 0;
  for (final (index, item) in items.indexed) {
    if (placed[index] != null) continue;
    final w = min(item.w.round(), columns), h = item.h.round();
    var x = mode == SectionMode.flow ? cursorX : 0;
    var y = mode == SectionMode.flow ? cursorY : 0;
    while (!free(x, y, w, h)) {
      x++;
      if (x + w > columns) {
        x = 0;
        y++;
      }
    }
    placed[index] = take(x, y, w, h);
    cursorX = x;
    cursorY = y;
  }
  return placed.cast();
}

/// How many rows [placements] reach down to; a fraction only in a
/// [SectionMode.free] section.
double rowCount(Iterable<Placement> placements) =>
    placements.fold(0, (rows, p) => max(rows, p.y + p.h));
