import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/resize_handles.dart';
import 'package:openlauncher/editor/snapping.dart';
import 'package:openlauncher/editor/tv_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// Where the item [id] is placed in [pane]: where it is drawn, which is as
/// its pane would have it.
Placement placementIn(Pane pane, String id) => placeItems(
  pane.shown,
  pane.columns,
  pane.mode,
)[pane.items.indexWhere((item) => item.id == id)];

/// Where [item] would go in [pane] if let go of [at] a point of its grid,
/// places and sizes going by [step] cells.
Drop dropAt(
  Pane pane,
  PaneMetrics metrics,
  Offset at,
  LayoutItem item,
  double step,
) {
  if (pane.mode == PaneMode.flow) {
    // In front of the first thing that comes after the pointer, reading
    // across and then down.
    final placed = placeItems(pane.shown, pane.columns, pane.mode);
    String? before;
    for (final (index, other) in pane.items.indexed) {
      if (other.id == item.id) continue;
      final rect = metrics.rectOf(placed[index]);
      if (at.dy < rect.top - metrics.gapY / 2 ||
          at.dy < rect.bottom + metrics.gapY / 2 && at.dx < rect.center.dx) {
        before = other.id;
        break;
      }
    }
    return Drop(pane.id, before: before);
  }
  // Held by its middle, and set down on whole cells; or, where things
  // can be anywhere and are not being kept to cells, just about where
  // it is let go. Only there does it keep a size that is not whole.
  final free = pane.mode == PaneMode.free;
  final w = (free ? item.w : item.w.roundToDouble())
      .clamp(free ? Pane.minFreeSpan : 1, pane.columns)
      .toDouble();
  final h = (free ? item.h : item.h.roundToDouble())
      .clamp(free ? Pane.minFreeSpan : 1, Pane.maxRows)
      .toDouble();
  final cell = metrics.cellAt(
    at - Offset(metrics.across(w) / 2, metrics.down(h) / 2),
  );
  return Drop(
    pane.id,
    x: snapTo(cell.dx, step).clamp(0, pane.columns - w).toDouble(),
    y: snapTo(cell.dy, step).clamp(0, 999).toDouble(),
  );
}

/// Where on the screen a sidebar on the edge [id] is when open, or with
/// [thickness], a strip that thick along that edge.
Rect barRect(Layout layout, String id, {double? thickness}) {
  final panel = layout.panel(id) ?? Panel.empty(id);
  final Size(:width, :height) = TvScreen.size;
  final across = panel.opensAcross;
  final w = across && thickness != null
      ? thickness
      : panel.openWidth.clamp(0.0, width);
  final h = !across && thickness != null
      ? thickness
      : panel.openHeight.clamp(0.0, height);
  return switch (panel.edge) {
    BarEdge.right => Rect.fromLTWH(width - w, (height - h) / 2, w, h),
    BarEdge.bottom => Rect.fromLTWH((width - w) / 2, height - h, w, h),
    BarEdge.top => Rect.fromLTWH((width - w) / 2, 0, w, h),
    _ => Rect.fromLTWH(0, (height - h) / 2, w, h),
  };
}

/// The smallest a thing can be made, in cells, when sizes go by [step].
double leastSpan(double step) => step < 1 ? Pane.minFreeSpan : 1;

/// The handles that can do something for a thing placed at [placed] in
/// [pane]: an edge has one if it can go outwards, there being room in the
/// pane, or inwards, the thing being more than a cell across; a corner
/// has one if both its edges do.
Set<ResizeHandle> resizeHandles(
  LayoutItem item,
  Placement placed,
  Pane pane,
  double least,
) {
  // An entity whose size its pane decides has none to change.
  final decided =
      (pane.itemW != null || pane.itemH != null) &&
      item.kind == ItemKind.prefab;
  if (decided) return const {};
  bool across(int side) =>
      side == 0 ||
      placed.w > least ||
      (side < 0 ? placed.x > 0 : placed.x + placed.w < pane.columns);
  bool down(int side) =>
      side == 0 ||
      placed.h > least ||
      (side < 0 ? placed.y > 0 : placed.h < Pane.maxRows);
  return {
    for (final handle in ResizeHandle.values)
      if (across(handle.dx) && down(handle.dy)) handle,
  };
}

/// The place and size, in cells, that a thing [placed] in [pane] has with
/// [handle] dragged [moved] from where it was taken hold of, places and
/// sizes going by [step] cells.
({double x, double y, double w, double h}) resizedTo(
  Pane pane,
  Placement placed,
  PaneMetrics metrics,
  ResizeHandle handle,
  Offset moved,
  double step,
) {
  final by = metrics.cellAt(moved);
  final columns = by.dx.round(), rows = by.dy.round();
  // The edge that is held goes to the nearest line: of the cells, or
  // where things are not kept to cells, of small parts of one. It can go
  // no further than leaves the least there can be, or than the pane.
  final least = leastSpan(step);
  final left = handle.dx < 0
      ? snapTo(placed.x + by.dx, step).clamp(0, placed.x + placed.w - least)
      : placed.x;
  final top = handle.dy < 0
      ? snapTo(placed.y + by.dy, step).clamp(0, placed.y + placed.h - least)
      : placed.y;
  final right = handle.dx > 0
      ? snapTo(
          placed.x + placed.w + by.dx,
          step,
        ).clamp(left + least, pane.columns)
      : placed.x + placed.w;
  final bottom = handle.dy > 0
      ? snapTo(
          placed.y + placed.h + by.dy,
          step,
        ).clamp(top + least, top + Pane.maxRows)
      : placed.y + placed.h;
  // Where things flow there is no place to keep or change, only a size:
  // any handle pulled outwards makes it bigger by that much.
  final flows = pane.mode == PaneMode.flow;
  return (
    x: left * 1.0,
    y: top * 1.0,
    w: flows
        ? (placed.w + handle.dx * columns).clamp(1, pane.columns) * 1.0
        : (right - left) * 1.0,
    h: flows
        ? (placed.h + handle.dy * rows).clamp(1, Pane.maxRows) * 1.0
        : (bottom - top) * 1.0,
  );
}
