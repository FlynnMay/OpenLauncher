import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/layout_model.dart';

/// The cells an item covers: column and row from zero, and its size. Whole
/// numbers except in a [PaneMode.free] section.
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
/// In [PaneMode.flow] the items follow one another the way CSS grid
/// auto-placement puts them, the same way the config page places them. In [PaneMode.grid] items sit where they say; any that
/// have no position, or whose position is taken, fill the first free space.
/// In [PaneMode.free] items are simply where they say, overlapping or
/// not; any without a position line up below those.
List<Placement> placeItems(List<LayoutItem> items, int columns, PaneMode mode) {
  if (mode == PaneMode.free) {
    double width(LayoutItem item) => min(item.w, columns * 1.0);
    // What has no position yet, such as a newly installed app, goes in rows
    // under everything that has one, rather than on top of it.
    final below = items
        .where((item) => item.x != null && item.y != null)
        .fold(0.0, (rows, item) => max(rows, item.y! + item.h))
        .ceilToDouble();
    var x = 0.0, y = below, rowHeight = 0.0;
    return [
      for (final item in items)
        if (item.x != null && item.y != null)
          Placement(item.x!, item.y!, width(item), item.h)
        else
          () {
            if (x > 0 && x + width(item) > columns) {
              x = 0;
              y += rowHeight;
              rowHeight = 0;
            }
            final placed = Placement(x, y, width(item), item.h);
            x += width(item);
            rowHeight = max(rowHeight, item.h);
            return placed;
          }(),
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
  if (mode == PaneMode.grid) {
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
    var x = mode == PaneMode.flow ? cursorX : 0;
    var y = mode == PaneMode.flow ? cursorY : 0;
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
/// [PaneMode.free] section.
double rowCount(Iterable<Placement> placements) =>
    placements.fold(0, (rows, p) => max(rows, p.y + p.h));
