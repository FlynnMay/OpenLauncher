import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/components/primitives.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/styled_box.dart';

/// Gives the initial focus to the first tile that asks.
class FirstFocus {
  bool _taken = false;

  /// True once only.
  bool take() => !_taken && (_taken = true);
}

/// Cell sizes of a pane at a given width.
@immutable
class PaneMetrics {
  /// From the width of its whole grid, which is wider than the pane when it
  /// scrolls across.
  PaneMetrics(Component pane, double width)
    : this._(pane, width, columnsOf(pane));

  /// From the width the pane shows.
  PaneMetrics.shown(Component pane, double width)
    : this._(pane, width, pane.columns);

  PaneMetrics._(Component pane, double width, int columns)
    : gapX = pane.spacingX,
      gapY = pane.spacingY,
      cellWidth = (width - (columns - 1) * pane.spacingX) / columns,
      _rowHeight = pane.rowHeight;

  final double gapX, gapY, cellWidth;
  final double? _rowHeight;

  /// The pane's row height, else from the cell width.
  double get cellHeight => _rowHeight ?? cellWidth / PaneGrid.cellRatio;

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

/// Wraps every pane's grid. Unused on the TV; the editor uses it to locate
/// panes.
class PaneFrame extends InheritedWidget {
  const PaneFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Component pane, Widget grid) wrap;

  @override
  bool updateShouldNotify(PaneFrame oldWidget) => wrap != oldWidget.wrap;
}

/// Lays a pane's children out on its cell grid.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.pane, required this.tile});

  final Component pane;
  final Widget Function(Component component) tile;

  /// Cell width over height.
  static const cellRatio = 1.45;

  @override
  Widget build(BuildContext context) {
    final pane = this.pane;
    final shown = pane.shown;
    final frame = context.dependOnInheritedWidgetOfExactType<PaneFrame>();
    final grid = LayoutBuilder(
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
    // Children can read the pane's variables.
    final scoped = pane.vars.isEmpty
        ? grid
        : Consumer(
            builder: (context, ref, child) => TemplateScope(
              values: scopeOf(
                ref.watch,
                pane.id,
                pane.vars,
                TemplateScope.of(context),
              ).inner,
              child: child!,
            ),
            child: grid,
          );
    return StyleScope.under(context, pane.style, scoped);
  }
}

/// A pane in its box: background, title and its grid, scrolling the ways the
/// pane says. Padding is inside the scroll area, so a focused tile can grow
/// into it.
class PaneBox extends ConsumerWidget {
  const PaneBox({
    super.key,
    required this.pane,
    required this.tile,
    this.shrink = false,
    this.placeholder,
  });

  final Component pane;
  final Widget Function(Component component) tile;

  /// As tall as what is in it, where it has the room to be.
  final bool shrink;

  /// Shown while there is nothing in it.
  final String? placeholder;

  static BorderRadius shapeOf(Component pane) =>
      styleShape(pane.box, Component.defaultCorner);

  static const _underTitle = 10.0;

  /// How far a focused tile may show past a pane with no background.
  static const overhang = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = this.pane;
    final outer = TemplateScope.of(context);
    final box = BoxStyle.of(readStyle(ref.watch, pane.style, outer));
    final padding = box.padding ?? Component.defaultPadding;
    // The title may read the pane's own variables.
    final title = !pane.title.contains('{{')
        ? pane.title
        : valueText(
            readTemplate(
              ref.watch,
              pane.title,
              scopeOf(ref.watch, pane.id, pane.vars, outer).own,
            ),
          );
    final titled = title.isNotEmpty;
    final fill = styleFill(box);
    final border = box.border;
    final shape = styleShape(box, Component.defaultCorner);
    final grid = PaneGrid(pane: pane, tile: tile);
    final padded = Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        titled ? _underTitle : padding,
        padding,
        padding,
      ),
      child: placeholder != null && pane.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  placeholder!,
                  style: const TextStyle(color: Colors.white60),
                ),
                grid,
              ],
            )
          : grid,
    );
    // What does not scroll is cut off at the box.
    final scroll = pane.scrollsDown
        ? SingleChildScrollView(clipBehavior: Clip.none, child: padded)
        : padded;
    final content = Column(
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titled)
          Padding(
            padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
            child: PaneTitle(title),
          ),
        shrink ? Flexible(child: scroll) : Expanded(child: scroll),
      ],
    );
    if (box.isEmpty) {
      return styleOpacity(
        box,
        ClipRect(clipper: const Inflated(PaneBox.overhang), child: content),
      );
    }
    final painted = DecoratedBox(
      decoration: BoxDecoration(
        color: fill.color,
        gradient: fill.gradient,
        borderRadius: shape,
        boxShadow: styleShadow(box),
      ),
      // The border is painted over the pane and takes no space.
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: border == null
              ? null
              : Border.all(color: Color(border), width: box.borderWidth),
        ),
        child: ClipRRect(borderRadius: shape, child: content),
      ),
    );
    return styleOpacity(box, painted);
  }
}

/// Clips [by] outside the box.
class Inflated extends CustomClipper<Rect> {
  const Inflated(this.by);

  final double by;

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(by);

  @override
  bool shouldReclip(Inflated oldClipper) => oldClipper.by != by;
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
