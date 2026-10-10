import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/styled_box.dart';

/// Hands the starting focus to the first tile that asks for it.
class FirstFocus {
  bool _taken = false;

  /// True once only.
  bool take() => !_taken && (_taken = true);
}

/// Lays a pane's entries out on its cell grid, filling the width given and
/// as tall as they need.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.view, required this.tile});

  final PaneView view;
  final Widget Function(Entry entry) tile;

  // The config page draws the same grid; see `TV` in assets/web/index.html.

  /// Width over height of one cell, label included.
  static const cellRatio = 1.45;

  @override
  Widget build(BuildContext context) {
    final pane = view.pane;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gapX = pane.spacingX, gapY = pane.spacingY;
        final cellWidth =
            (constraints.maxWidth - (pane.columns - 1) * gapX) / pane.columns;
        final cellHeight = cellWidth / cellRatio;
        double span(double cells, double cell, double gap) =>
            cells * cell + (cells - 1) * gap;
        final placements = placeItems(pane.items, pane.columns, pane.mode);
        final rows = rowCount(placements);
        return SizedBox(
          height: rows == 0 ? 0 : span(rows, cellHeight, gapY),
          child: Stack(
            // Focused tiles grow past their cell.
            clipBehavior: Clip.none,
            children: [
              for (final (index, entry) in view.entries.indexed)
                Positioned(
                  key: ValueKey(entry.item.id),
                  left: placements[index].x * (cellWidth + gapX),
                  top: placements[index].y * (cellHeight + gapY),
                  width: span(placements[index].w, cellWidth, gapX),
                  height: span(placements[index].h, cellHeight, gapY),
                  child: tile(entry),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A pane inside another: its background, its title and its own grid. What
/// does not fit its height is reached by moving the focus down: it scrolls.
class PaneBox extends StatelessWidget {
  const PaneBox({super.key, required this.view, required this.tile});

  final PaneView view;
  final Widget Function(Entry entry) tile;

  @override
  Widget build(BuildContext context) {
    final pane = view.pane;
    return StyledBox(
      style: pane.style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pane.title.isNotEmpty) PaneTitle(pane.title),
          Expanded(
            child: ClipRect(
              clipper: const _Roomy(),
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                child: PaneGrid(view: view, tile: tile),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips a little outside the box, so a focused tile at the edge can grow
/// without being cut while what has scrolled away stays hidden.
class _Roomy extends CustomClipper<Rect> {
  const _Roomy();

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(10);

  @override
  bool shouldReclip(_Roomy oldClipper) => false;
}

class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Colors.white70),
    ),
  );
}
