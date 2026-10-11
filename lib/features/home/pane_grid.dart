import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
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
  PaneMetrics(Component pane, double width)
    : gapX = pane.spacingX,
      gapY = pane.spacingY,
      cellWidth = (width - (pane.columns - 1) * pane.spacingX) / pane.columns,
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
  const PaneGrid({
    super.key,
    required this.pane,
    required this.tile,
    this.owner,
  });

  final Component pane;

  /// The id its runtime variables are stored under, if not its own: a
  /// folder's pane uses the folder's.
  final String? owner;
  final Widget Function(Component component) tile;

  /// Cell width over height.
  static const cellRatio = 1.45;

  @override
  Widget build(BuildContext context) {
    final pane = this.pane;
    final shown = pane.shown;
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final metrics = PaneMetrics(pane, constraints.maxWidth);
        final placements = placeItems(shown, pane.columns, pane.mode);
        final rows = rowCount(placements);
        return SizedBox(
          height: rows == 0 ? 0 : metrics.down(rows),
          child: PaneScope(
            panes: [...PaneScope.of(context), pane.id],
            child: Stack(
              // Focused tiles grow past their cell.
              clipBehavior: Clip.none,
              children: [
                for (final (index, child) in shown.indexed)
                  if (!child.hidden)
                    Positioned.fromRect(
                      key: ValueKey(child.id),
                      rect: metrics.rectOf(placements[index]),
                      child: tile(child),
                    ),
              ],
            ),
          ),
        );
      },
    );
    // Children can read the pane's variables.
    final scoped = pane.vars.isEmpty
        ? grid
        : Consumer(
            builder: (context, ref, child) => TemplateScope(
              values: scopeOf(
                ref.watch,
                owner ?? pane.id,
                pane.vars,
                TemplateScope.of(context),
              ).inner,
              child: child!,
            ),
            child: grid,
          );
    final styled = StyleScope.under(context, pane.style, scoped);
    final frame = context.dependOnInheritedWidgetOfExactType<PaneFrame>();
    return frame == null ? styled : frame.wrap(pane, styled);
  }
}

/// A nested pane: background, title and a scrolling grid. Padding is inside
/// the scroll area, so a focused tile can grow into it.
class PaneBox extends ConsumerWidget {
  const PaneBox({super.key, required this.pane, required this.tile});

  final Component pane;
  final Widget Function(Component component) tile;

  static BorderRadius shapeOf(Component pane) =>
      styleShape(pane.box, Component.defaultCorner);

  static const _underTitle = 10.0;

  /// How far a focused tile may show past a pane with no background.
  static const _overhang = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = this.pane;
    final box = BoxStyle.of(
      readStyle(ref.watch, pane.style, TemplateScope.of(context)),
    );
    final padding = box.padding ?? Component.defaultPadding;
    final titled = pane.title.isNotEmpty;
    final fill = styleFill(box);
    final border = box.border;
    final shape = styleShape(box, Component.defaultCorner);
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
            child: PaneGrid(pane: pane, tile: tile),
          ),
        ),
      ],
    );
    if (box.isEmpty) {
      return styleOpacity(
        box,
        ClipRect(clipper: const _Inflated(_overhang), child: content),
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
