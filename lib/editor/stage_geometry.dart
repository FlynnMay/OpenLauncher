import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/resize_handles.dart';
import 'package:openlauncher/editor/snapping.dart';
import 'package:openlauncher/editor/tv_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// [id]'s placement in [pane], as drawn.
Placement placementIn(Component pane, String id) => placeItems(
  pane.shown,
  pane.columns,
  pane.mode,
)[pane.children.indexWhere((item) => item.id == id)];

/// The drop for [item] released [at] a point of [pane]'s grid, snapped to
/// [step].
Drop dropAt(
  Component pane,
  PaneMetrics metrics,
  Offset at,
  Component item,
  double step,
) {
  if (pane.mode == PaneMode.flow) {
    // Before the first child after the pointer, in reading order.
    final placed = placeItems(pane.shown, pane.columns, pane.mode);
    String? before;
    for (final (index, other) in pane.children.indexed) {
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
  // Held by its centre and snapped to [step]. Fractional sizes only in an
  // unsnapped free pane.
  final free = pane.mode == PaneMode.free;
  final w = (free ? item.w : item.w.roundToDouble())
      .clamp(free ? Component.minFreeSpan : 1, pane.columns)
      .toDouble();
  final h = (free ? item.h : item.h.roundToDouble())
      .clamp(free ? Component.minFreeSpan : 1, Component.maxRows)
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

/// The open rect of the sidebar on edge [id], or a strip [thickness] thick.
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

/// Smallest size in cells at [step].
double leastSpan(double step) => step < 1 ? Component.minFreeSpan : 1;

/// The handles that can do something: an edge needs room to grow or more than
/// one cell to shrink; a corner needs both its edges.
Set<ResizeHandle> resizeHandles(
  Component item,
  Placement placed,
  Component pane,
  double least,
) {
  // The pane sets its size.
  final decided = (pane.itemW != null || pane.itemH != null) && item.isInstance;
  if (decided) return const {};
  bool across(int side) =>
      side == 0 ||
      placed.w > least ||
      (side < 0 ? placed.x > 0 : placed.x + placed.w < pane.columns);
  bool down(int side) =>
      side == 0 ||
      placed.h > least ||
      (side < 0 ? placed.y > 0 : placed.h < Component.maxRows);
  return {
    for (final handle in ResizeHandle.values)
      if (across(handle.dx) && down(handle.dy)) handle,
  };
}

/// The cells for [placed] with [handle] dragged by [moved], snapped to
/// [step].
({double x, double y, double w, double h}) resizedTo(
  Component pane,
  Placement placed,
  PaneMetrics metrics,
  ResizeHandle handle,
  Offset moved,
  double step,
) {
  final by = metrics.cellAt(moved);
  final columns = by.dx.round(), rows = by.dy.round();
  // The dragged edge snaps to the nearest line, within the minimum size and
  // the pane.
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
        ).clamp(top + least, top + Component.maxRows)
      : placed.y + placed.h;
  // In a flow pane only the size changes.
  final flows = pane.mode == PaneMode.flow;
  return (
    x: left * 1.0,
    y: top * 1.0,
    w: flows
        ? (placed.w + handle.dx * columns).clamp(1, pane.columns) * 1.0
        : (right - left) * 1.0,
    h: flows
        ? (placed.h + handle.dy * rows).clamp(1, Component.maxRows) * 1.0
        : (bottom - top) * 1.0,
  );
}
