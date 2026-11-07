import 'dart:math';

import 'package:meta/meta.dart';
import 'package:openlauncher_domain/layout/layout_enums.dart';
import 'package:openlauncher_domain/layout/tree.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/node.dart';

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
/// One off the cells (docked or an Overlay) gets an empty placement.
List<Placement> placeItems(List<Node> items, int columns, LayoutMode mode) {
  if (items.any((item) => item.offCells)) {
    return _placedAmongOffCells(items, columns, mode);
  }
  // Without a layout children sit where their transforms say.
  if (mode == LayoutMode.free) {
    return [for (final _ in items) _noCells];
  }
  final cells = _TakenCells(columns);
  final placed = List<Placement?>.filled(items.length, null);
  if (mode == LayoutMode.grid) _placeWhereAsked(items, cells, placed);
  _placeInOrder(items, cells, placed, flow: mode != LayoutMode.grid);
  return placed.cast();
}

const _noCells = Placement(0, 0, 0, 0);

List<Placement> _placedAmongOffCells(
  List<Node> items,
  int columns,
  LayoutMode mode,
) {
  final rest = placeItems(
    [
      for (final item in items)
        if (!item.offCells) item,
    ],
    columns,
    mode,
  ).iterator;
  return [
    for (final item in items)
      item.offCells ? _noCells : (rest..moveNext()).current,
  ];
}

/// Grid items with a position that is free keep it.
void _placeWhereAsked(
  List<Node> items,
  _TakenCells cells,
  List<Placement?> placed,
) {
  for (final (index, item) in items.indexed) {
    final x = item.x?.round(), y = item.y?.round();
    final w = min(item.w.round(), cells.columns), h = item.h.round();
    if (x != null && y != null && cells.isFree(x, y, w, h)) {
      placed[index] = cells.take(x, y, w, h);
    }
  }
}

/// The cursor only moves forward, keeping order. Row and column containers
/// are treated as flow.
void _placeInOrder(
  List<Node> items,
  _TakenCells cells,
  List<Placement?> placed, {
  required bool flow,
}) {
  var cursorX = 0, cursorY = 0;
  for (final (index, item) in items.indexed) {
    if (placed[index] != null) continue;
    final w = min(item.w.round(), cells.columns), h = item.h.round();
    var x = flow ? cursorX : 0;
    var y = flow ? cursorY : 0;
    while (!cells.isFree(x, y, w, h)) {
      x++;
      if (x + w > cells.columns) {
        x = 0;
        y++;
      }
    }
    placed[index] = cells.take(x, y, w, h);
    cursorX = x;
    cursorY = y;
  }
}

class _TakenCells {
  _TakenCells(this.columns);

  final int columns;
  final _taken = <(int, int)>{};

  bool isFree(int x, int y, int w, int h) =>
      x + w <= columns && !_covered(x, y, w, h).any(_taken.contains);

  Placement take(int x, int y, int w, int h) {
    _taken.addAll(_covered(x, y, w, h));
    return Placement(x * 1.0, y * 1.0, w * 1.0, h * 1.0);
  }

  Iterable<(int, int)> _covered(int x, int y, int w, int h) => w <= 0 || h <= 0
      ? const []
      : Iterable.generate(w * h, (cell) => (x + cell % w, y + cell ~/ w));
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
