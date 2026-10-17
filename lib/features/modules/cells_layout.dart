import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/layout_drawer.dart';

/// Cell sizes of a container at a given width.
@immutable
class CellMetrics {
  /// From the width of its whole grid, which is wider than the container when
  /// it scrolls across.
  CellMetrics(Node container, double width)
    : this._(container, width, columnsOf(container));

  /// From the width the container shows.
  CellMetrics.shown(Node container, double width)
    : this._(container, width, container.columns);

  CellMetrics._(Node container, double width, int columns)
    : gapX = container.spacingX,
      gapY = container.spacingY,
      cellWidth = (width - (columns - 1) * container.spacingX) / columns,
      _rowHeight = container.rowHeight;

  /// Cell width over height.
  static const cellRatio = 1.45;

  final double gapX, gapY, cellWidth;
  final double? _rowHeight;

  /// The container's row height, else from the cell width.
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

/// Lays [container]'s children out on its cells (flow or grid), scrolling
/// across when it says so.
class CellsLayout extends StatelessWidget {
  const CellsLayout({super.key, required this.container, required this.tile});

  final Node container;
  final Widget Function(Node child) tile;

  @override
  Widget build(BuildContext context) {
    final container = this.container;
    final shown = container.shown;
    final frame = context.dependOnInheritedWidgetOfExactType<LayoutFrame>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = CellMetrics.shown(container, constraints.maxWidth);
        final placements = placementsOf(container);
        final rows = rowCount(placements);
        final across = container.scrollsAcross;
        final cells = SizedBox(
          width: across
              ? metrics.across(columnsOf(container, placements) * 1.0)
              : null,
          height: rows == 0 ? 0 : metrics.down(rows),
          child: ContainerScope(
            containers: [...ContainerScope.of(context), container.id],
            child: Stack(
              // Focused tiles grow past their cell.
              clipBehavior: Clip.none,
              children: [
                for (final (index, child) in shown.indexed)
                  // A docked container is drawn by its layer.
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
        final framed = frame == null ? cells : frame.wrap(container, cells);
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
