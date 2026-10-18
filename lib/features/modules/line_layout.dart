import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Lays a row or column's children in a line, each sized by its flex, its
/// aspect or its natural size. Its scroll is drawn around it.
class LineLayout extends StatelessWidget {
  const LineLayout({
    super.key,
    required this.container,
    required this.tile,
    this.inner = false,
    this.hug = false,
  });

  final Node container;

  /// Draws a child; [shrink] asks for its natural size.
  final Widget Function(Node child, {required bool shrink}) tile;

  /// Nested in another row or column.
  final bool inner;

  /// As long as what is in it, where it has the room; what has a flex takes
  /// no more than it needs.
  final bool hug;

  /// Whether it scrolls along its line.
  bool get _scrolls => container.mode == LayoutMode.row
      ? container.scrollsAcross
      : container.scrollsDown;

  Widget? _place(Node child) {
    if (child.offCells || child.hidden && !child.keep) return null;
    // Nothing is shared out when the container is fitted or scrolls.
    final flex = _scrolls ? null : child.flex;
    final sized = !container.fit && (flex != null || child.aspect != null);
    Widget placed = KeyedSubtree(
      key: ValueKey(child.id),
      child: tile(child, shrink: !sized),
    );
    // Keeps its space while hidden.
    if (child.keep) {
      placed = Visibility.maintain(visible: !child.hidden, child: placed);
    }
    if (container.fit) return placed;
    if (child.aspect case final aspect?) {
      placed = AspectRatio(aspectRatio: aspect, child: placed);
    }
    return flex == null
        ? placed
        : Flexible(
            flex: flex.round(),
            fit: hug ? FlexFit.loose : FlexFit.tight,
            child: placed,
          );
  }

  @override
  Widget build(BuildContext context) {
    final row = container.mode == LayoutMode.row;
    final flex = Flex(
      direction: row ? Axis.horizontal : Axis.vertical,
      mainAxisSize: container.fit || inner || hug || _scrolls
          ? MainAxisSize.min
          : MainAxisSize.max,
      mainAxisAlignment: inner
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: switch (container.align) {
        'start' => CrossAxisAlignment.start,
        'end' => CrossAxisAlignment.end,
        'center' => CrossAxisAlignment.center,
        'stretch' => CrossAxisAlignment.stretch,
        // A fitted row cannot stretch.
        _ when row || container.fit => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.stretch,
      },
      spacing: container.gap,
      children: [for (final child in container.shown) ?_place(child)],
    );
    // Scaled to the box once, at the top level.
    return container.fit && !inner && !_scrolls ? FittedBox(child: flex) : flex;
  }
}
