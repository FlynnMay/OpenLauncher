import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';

/// The cells a component covers. Fractions only in [PaneMode.free].
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

/// The placement of each of [items] on a grid [columns] wide.
///
/// Flow follows CSS grid auto-placement. Grid uses explicit positions;
/// unplaced or colliding items take the first free space. Free uses positions
/// as given; unplaced items line up below the rest.
///
/// A docked pane takes no cells: it gets an empty placement.
List<Placement> placeItems(List<Component> items, int columns, PaneMode mode) {
  if (items.any((item) => item.isDocked)) {
    final rest = placeItems(
      [
        for (final item in items)
          if (!item.isDocked) item,
      ],
      columns,
      mode,
    ).iterator;
    return [
      for (final item in items)
        item.isDocked
            ? const Placement(0, 0, 0, 0)
            : (rest..moveNext()).current,
    ];
  }
  if (mode == PaneMode.free) {
    double width(Component item) => min(item.w, columns * 1.0);
    // Unplaced items go below everything that has a position.
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

  // The cursor only moves forward, keeping order. Row and column panes are
  // treated as flow.
  final flow = mode != PaneMode.grid;
  var cursorX = 0, cursorY = 0;
  for (final (index, item) in items.indexed) {
    if (placed[index] != null) continue;
    final w = min(item.w.round(), columns), h = item.h.round();
    var x = flow ? cursorX : 0;
    var y = flow ? cursorY : 0;
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

/// The number of rows [placements] reach.
double rowCount(Iterable<Placement> placements) =>
    placements.fold(0, (rows, p) => max(rows, p.y + p.h));
