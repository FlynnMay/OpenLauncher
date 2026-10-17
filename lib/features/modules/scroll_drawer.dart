import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/modules/scroll_bars.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';

/// Scrolls a whole screen of tiles, a layer's root or a docked pane, which
/// centres the focused one.
class ScreenScrollController extends ScrollController {}

/// [child] scrolling down as a whole screen of tiles: see
/// [ScreenScrollController].
class ScreenScrollView extends StatefulWidget {
  const ScreenScrollView({
    super.key,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final Clip clipBehavior;

  @override
  State<ScreenScrollView> createState() => _ScreenScrollViewState();
}

class _ScreenScrollViewState extends State<ScreenScrollView> {
  final _controller = ScreenScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _controller,
    clipBehavior: widget.clipBehavior,
    child: widget.child,
  );
}

/// [child] scrolled the ways [node]'s Scroll says and its Layout allows,
/// under its scroll bars, which look as [values] (its Scroll module's,
/// templates read) say. Cells scroll across inside their grid; a row or
/// column scrolls along its line. [screen] centres the focused tile.
Widget scrolled(
  Node node,
  Map<String, Object?> values,
  Widget child, {
  bool screen = false,
}) {
  if (node.mode.inLine) {
    final row = node.mode == PaneMode.row;
    if (!(row ? node.scrollsAcross : node.scrollsDown)) return child;
    // Cut off a little outside, so a focused child can grow.
    return ClipRect(
      clipper: const Inflated(overhang),
      child: PaneScrollbars.over(
        node,
        values,
        SingleChildScrollView(
          scrollDirection: row ? Axis.horizontal : Axis.vertical,
          clipBehavior: Clip.none,
          child: child,
        ),
      ),
    );
  }
  return PaneScrollbars.over(
    node,
    values,
    !node.scrollsDown
        ? child
        : screen
        ? ScreenScrollView(clipBehavior: Clip.none, child: child)
        : SingleChildScrollView(clipBehavior: Clip.none, child: child),
  );
}
