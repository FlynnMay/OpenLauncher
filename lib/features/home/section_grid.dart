import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Lays a section's entries out on its cell grid, filling the width given.
class SectionGrid extends StatelessWidget {
  const SectionGrid({super.key, required this.view, required this.tile});

  final SectionView view;
  final Widget Function(Entry entry, int index) tile;

  static const _gapX = 20.0, _gapY = 16.0;

  /// Width over height of one cell, label included.
  static const _cellRatio = 1.45;

  @override
  Widget build(BuildContext context) {
    final section = view.section;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - (section.columns - 1) * _gapX) /
            section.columns;
        final cellHeight = cellWidth / _cellRatio;
        double span(double cells, double cell, double gap) =>
            cells * cell + (cells - 1) * gap;
        final placements = placeItems(
          section.items,
          section.columns,
          section.mode,
        );
        final rows = rowCount(placements);
        return SizedBox(
          height: rows == 0 ? 0 : span(rows, cellHeight, _gapY),
          child: Stack(
            // Focused tiles grow past their cell.
            clipBehavior: Clip.none,
            children: [
              for (final (index, entry) in view.entries.indexed)
                Positioned(
                  key: ValueKey(entry.item.id),
                  left: placements[index].x * (cellWidth + _gapX),
                  top: placements[index].y * (cellHeight + _gapY),
                  width: span(placements[index].w, cellWidth, _gapX),
                  height: span(placements[index].h, cellHeight, _gapY),
                  child: tile(entry, index),
                ),
            ],
          ),
        );
      },
    );
  }
}
