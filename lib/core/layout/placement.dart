import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/tree.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// The cells a node covers.
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
/// unplaced or colliding items take the first free space. Without a layout
/// there are no cells.
///
/// A docked container takes no cells: it gets an empty placement.
List<Placement> placeItems(List<Node> items, int columns, LayoutMode mode) {
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
  // Without a layout children sit where their transforms say.
  if (mode == LayoutMode.free) {
    return [for (final _ in items) const Placement(0, 0, 0, 0)];
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
  if (mode == LayoutMode.grid) {
    for (final (index, item) in items.indexed) {
      final x = item.x?.round(), y = item.y?.round();
      final w = min(item.w.round(), columns), h = item.h.round();
      if (x != null && y != null && free(x, y, w, h)) {
        placed[index] = take(x, y, w, h);
      }
    }
  }

  // The cursor only moves forward, keeping order. Row and column containers are
  // treated as flow.
  final flow = mode != LayoutMode.grid;
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

/// [container]'s children placed as drawn.
List<Placement> placementsOf(Node container) =>
    placeItems(container.shown, container.reach, container.mode);

/// The columns of [container]'s grid: its own, and as many more as its children
/// reach when it scrolls across.
int columnsOf(Node container, [List<Placement>? placements]) =>
    !container.scrollsAcross
    ? container.columns
    : (placements ?? placementsOf(container)).fold(
        container.columns,
        (columns, p) => max(columns, (p.x + p.w).ceil()),
      );

/// The number of rows [placements] reach.
double rowCount(Iterable<Placement> placements) =>
    placements.fold(0, (rows, p) => max(rows, p.y + p.h));
