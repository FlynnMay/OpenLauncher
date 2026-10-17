import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/layout_drawer.dart';

/// Cell sizes of a pane at a given width.
@immutable
class PaneMetrics {
  /// From the width of its whole grid, which is wider than the pane when it
  /// scrolls across.
  PaneMetrics(Node pane, double width) : this._(pane, width, columnsOf(pane));

  /// From the width the pane shows.
  PaneMetrics.shown(Node pane, double width)
    : this._(pane, width, pane.columns);

  PaneMetrics._(Node pane, double width, int columns)
    : gapX = pane.spacingX,
      gapY = pane.spacingY,
      cellWidth = (width - (columns - 1) * pane.spacingX) / columns,
      _rowHeight = pane.rowHeight;

  /// Cell width over height.
  static const cellRatio = 1.45;

  final double gapX, gapY, cellWidth;
  final double? _rowHeight;

  /// The pane's row height, else from the cell width.
  double get cellHeight => _rowHeight ?? cellWidth / cellRatio;

  /// Width of [cells] columns, gaps included.
  double across(double cells) => cells * cellWidth + (cells - 1) * gapX;

  double down(double cells) => cells * cellHeight + (cells - 1) * gapY;

  Rect rectOf(Placement placement) => Rect.fromLTWH(
    placement.x * (cellWidth + gapX),
    placement.y * (cellHeight + gapY),
    across(placement.w),
    down(placement.h),
  );

  /// The fractional column and row at a point.
  Offset cellAt(Offset point) =>
      Offset(point.dx / (cellWidth + gapX), point.dy / (cellHeight + gapY));
}

/// Lays [pane]'s children out on its cells (flow or grid), scrolling across
/// when it says so.
class CellsLayout extends StatelessWidget {
  const CellsLayout({super.key, required this.pane, required this.tile});

  final Node pane;
  final Widget Function(Node child) tile;

  @override
  Widget build(BuildContext context) {
    final pane = this.pane;
    final shown = pane.shown;
    final frame = context.dependOnInheritedWidgetOfExactType<PaneFrame>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = PaneMetrics.shown(pane, constraints.maxWidth);
        final placements = placementsOf(pane);
        final rows = rowCount(placements);
        final across = pane.scrollsAcross;
        final cells = SizedBox(
          width: across
              ? metrics.across(columnsOf(pane, placements) * 1.0)
              : null,
          height: rows == 0 ? 0 : metrics.down(rows),
          child: PaneScope(
            panes: [...PaneScope.of(context), pane.id],
            child: Stack(
              // Focused tiles grow past their cell.
              clipBehavior: Clip.none,
              children: [
                for (final (index, child) in shown.indexed)
                  // A docked pane is drawn by its layer.
                  if (!child.hidden && !child.isDocked)
                    Positioned.fromRect(
                      key: ValueKey(child.id),
                      rect: metrics.rectOf(placements[index]),
                      child: tile(child),
                    ),
              ],
            ),
          ),
        );
        // Framed inside the scroll area, so the editor finds the whole grid.
        final framed = frame == null ? cells : frame.wrap(pane, cells);
        return across
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: framed,
              )
            : framed;
      },
    );
  }
}
