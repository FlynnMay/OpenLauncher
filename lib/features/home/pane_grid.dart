import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
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
          // What is in here is in this pane, inside whichever it is in.
          child: PaneScope(
            panes: [...PaneScope.of(context), pane.id],
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
          ),
        );
      },
    );
  }
}

/// A pane inside another: its background, its title and its own grid.
///
/// Its padding is the same with or without a background, and belongs to the
/// part that scrolls: a focused card grows into it and is cut only at the
/// pane's own edge. What does not fit the pane's height is reached by moving
/// the focus down.
class PaneBox extends StatelessWidget {
  const PaneBox({super.key, required this.view, required this.tile});

  final PaneView view;
  final Widget Function(Entry entry) tile;

  static const _radius = 14.0;

  /// The gap between a title and what is under it.
  static const _underTitle = 10.0;

  /// How far past its edge a pane with no background lets a focused card
  /// show. With a background, the edge is the edge.
  static const _overhang = 12.0;

  @override
  Widget build(BuildContext context) {
    final pane = view.pane;
    final padding = pane.padding ?? Pane.defaultPadding;
    final titled = pane.title.isNotEmpty;
    final fill = styleFill(pane.style);
    final border = pane.style.border;
    final shape = BorderRadius.circular(_radius);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titled)
          Padding(
            padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
            child: PaneTitle(pane.title),
          ),
        Expanded(
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(
              padding,
              titled ? _underTitle : padding,
              padding,
              padding,
            ),
            child: PaneGrid(view: view, tile: tile),
          ),
        ),
      ],
    );
    if (pane.style.isEmpty) {
      return ClipRect(clipper: const _Inflated(_overhang), child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill.color,
        gradient: fill.gradient,
        borderRadius: shape,
      ),
      // The outline is drawn over the pane, not around it: it takes no room.
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: border == null
              ? null
              : Border.all(color: Color(border), width: 2),
        ),
        child: ClipRRect(borderRadius: shape, child: content),
      ),
    );
  }
}

/// Clips a little outside the box.
class _Inflated extends CustomClipper<Rect> {
  const _Inflated(this.by);

  final double by;

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(by);

  @override
  bool shouldReclip(_Inflated oldClipper) => oldClipper.by != by;
}

class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: Colors.white70),
  );
}
