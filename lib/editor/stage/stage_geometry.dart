import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/stage/resize_handles.dart';
import 'package:openlauncher/editor/stage/snapping.dart';
import 'package:openlauncher/editor/stage/tv_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// [id]'s placement in [pane], as drawn.
Placement placementIn(Node pane, String id) =>
    placementsOf(pane)[pane.children.indexWhere((item) => item.id == id)];

/// [id]'s rect in [pane]'s grid, which is [size]: on its cells, or where its
/// transform puts it.
Rect rectIn(Node pane, String id, PaneMetrics metrics, Size size) =>
    pane.mode == PaneMode.free
    ? pane.children.firstWhere((item) => item.id == id).transform.rectIn(size)
    : metrics.rectOf(placementIn(pane, id));

/// The drop for [item] released [at] a point of [pane]'s grid, which is
/// [size], snapped to [step].
Drop dropAt(
  Node pane,
  PaneMetrics metrics,
  Size size,
  Offset at,
  Node item,
  double step,
) {
  if (pane.mode == PaneMode.free) {
    // Held by its centre, at the size it has here or its cells' size.
    final rect = pane.children.any((other) => other.id == item.id)
        ? item.transform.rectIn(size)
        : Offset.zero & Size(metrics.across(item.w), metrics.down(item.h));
    final topLeft = at - rect.size.center(Offset.zero);
    return Drop(
      pane.id,
      rect:
          Offset(snapTo(topLeft.dx, step), snapTo(topLeft.dy, step)) &
          rect.size,
      size: size,
    );
  }
  if (pane.mode == PaneMode.flow) {
    // Before the first child after the pointer, in reading order.
    final placed = placementsOf(pane);
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
  // Held by its centre and snapped to [step].
  final w = item.w.roundToDouble().clamp(1, pane.reach).toDouble();
  final h = item.h.roundToDouble().clamp(1, SizingModule.maxRows).toDouble();
  final cell = metrics.cellAt(
    at - Offset(metrics.across(w) / 2, metrics.down(h) / 2),
  );
  return Drop(
    pane.id,
    x: snapTo(cell.dx, step).clamp(0, pane.reach - w).toDouble(),
    y: snapTo(cell.dy, step).clamp(0, 999).toDouble(),
  );
}

/// The open rect of the pane docked to [edge], or a strip [thickness] thick.
Rect barRect(Layout layout, String edge, {double? thickness}) {
  final pane =
      barOn(layout, edge) ??
      Node.pane(id: edge).withValue(dockModule.name, 'position', edge);
  final Size(:width, :height) = TvScreen.size;
  final across = pane.opensAcross;
  final w = across && thickness != null
      ? thickness
      : pane.openWidth.clamp(0.0, width);
  final h = !across && thickness != null
      ? thickness
      : (pane.openHeight ?? height).clamp(0.0, height);
  return switch (pane.edge) {
    BarEdge.right => Rect.fromLTWH(width - w, (height - h) / 2, w, h),
    BarEdge.bottom => Rect.fromLTWH((width - w) / 2, height - h, w, h),
    BarEdge.top => Rect.fromLTWH((width - w) / 2, 0, w, h),
    _ => Rect.fromLTWH(0, (height - h) / 2, w, h),
  };
}

/// Smallest size of something without a layout around it, in TV pixels.
const leastSide = 8.0;

/// [rect] with [handle] dragged by [moved], snapped to [step].
Rect resizedRect(Rect rect, ResizeHandle handle, Offset moved, double step) {
  final left = handle.dx < 0
      ? snapTo(
          rect.left + moved.dx,
          step,
        ).clamp(double.negativeInfinity, rect.right - leastSide)
      : rect.left;
  final top = handle.dy < 0
      ? snapTo(
          rect.top + moved.dy,
          step,
        ).clamp(double.negativeInfinity, rect.bottom - leastSide)
      : rect.top;
  final right = handle.dx > 0
      ? snapTo(
          rect.right + moved.dx,
          step,
        ).clamp(left + leastSide, double.infinity)
      : rect.right;
  final bottom = handle.dy > 0
      ? snapTo(
          rect.bottom + moved.dy,
          step,
        ).clamp(top + leastSide, double.infinity)
      : rect.bottom;
  return Rect.fromLTRB(left, top, right, bottom);
}

/// The handles that can do something: an edge needs room to grow or more than
/// one cell to shrink; a corner needs both its edges.
Set<ResizeHandle> resizeHandles(Node item, Placement placed, Node pane) {
  // Without a layout every edge moves.
  if (pane.mode == PaneMode.free) return ResizeHandle.values.toSet();
  // The pane sets its size.
  final decided = (pane.itemW != null || pane.itemH != null) && item.isInstance;
  if (decided) return const {};
  const least = 1;
  bool across(int side) =>
      side == 0 ||
      placed.w > least ||
      (side < 0 ? placed.x > 0 : placed.x + placed.w < pane.reach);
  bool down(int side) =>
      side == 0 ||
      placed.h > least ||
      (side < 0 ? placed.y > 0 : placed.h < SizingModule.maxRows);
  return {
    for (final handle in ResizeHandle.values)
      if (across(handle.dx) && down(handle.dy)) handle,
  };
}

/// The cells for [placed] with [handle] dragged by [moved], snapped to
/// [step].
({double x, double y, double w, double h}) resizedTo(
  Node pane,
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
  const least = 1;
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
        ).clamp(left + least, pane.reach)
      : placed.x + placed.w;
  final bottom = handle.dy > 0
      ? snapTo(
          placed.y + placed.h + by.dy,
          step,
        ).clamp(top + least, top + SizingModule.maxRows)
      : placed.y + placed.h;
  // In a flow pane only the size changes.
  final flows = pane.mode == PaneMode.flow;
  return (
    x: left * 1.0,
    y: top * 1.0,
    w: flows
        ? (placed.w + handle.dx * columns).clamp(1, pane.reach) * 1.0
        : (right - left) * 1.0,
    h: flows
        ? (placed.h + handle.dy * rows).clamp(1, SizingModule.maxRows) * 1.0
        : (bottom - top) * 1.0,
  );
}
