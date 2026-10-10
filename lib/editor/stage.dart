import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/home/styled_box.dart';

/// The TV's home screen at the TV's own size, drawn by the TV's own
/// widgets, on which things are dropped and moved about.
class Stage extends ConsumerStatefulWidget {
  const Stage({super.key, required this.state});

  final TvState state;

  /// The TV's screen, in the units everything on it is measured in.
  static const size = Size(960, 540);

  @override
  ConsumerState<Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<Stage> {
  final _screen = GlobalKey();

  /// Where each pane's cells, and each pane inside another, are drawn.
  final _grids = <String, GlobalKey>{}, _boxes = <String, GlobalKey>{};

  /// Where what is being dragged would land, on the screen.
  Rect? _marker;

  static RenderBox? _box(GlobalKey? key) =>
      switch (key?.currentContext?.findRenderObject()) {
        final RenderBox box when box.attached && box.hasSize => box,
        _ => null,
      };

  Widget _frame(Pane pane, Widget grid) => KeyedSubtree(
    key: _grids.putIfAbsent(pane.id, GlobalKey.new),
    child: grid,
  );

  /// Where [dragged] would go if let go of at [pointer], and where on the
  /// screen that is; null over nothing that would take it.
  ({Drop drop, Rect marker})? _target(Offset pointer, Dragged dragged) {
    final layout = widget.state.layout;
    final item = dragged.item;
    // The innermost pane under the pointer, other than the one dragged.
    var pane = layout.home.root;
    for (Pane? inner = pane; inner != null;) {
      pane = inner;
      inner = null;
      for (final other in pane.items) {
        final box = _box(_boxes[other.pane?.id]);
        if (other.id != item.id &&
            box != null &&
            (Offset.zero & box.size).contains(box.globalToLocal(pointer))) {
          inner = other.pane;
        }
      }
    }
    final grid = _box(_grids[pane.id]), screen = _box(_screen);
    if (grid == null || screen == null) return null;
    if (refusal(layout, item, pane.id) != null) return null;

    final metrics = PaneMetrics(pane, grid.size.width);
    final at = grid.globalToLocal(pointer);
    final Drop drop;
    if (pane.mode == PaneMode.flow) {
      // In front of the first thing that comes after the pointer, reading
      // across and then down.
      final placed = placeItems(pane.items, pane.columns, pane.mode);
      String? before;
      for (final (index, other) in pane.items.indexed) {
        if (other.id == item.id) continue;
        final rect = metrics.rectOf(placed[index]);
        if (at.dy < rect.top - metrics.gapY / 2 ||
            at.dy < rect.bottom + metrics.gapY / 2 && at.dx < rect.center.dx) {
          before = other.id;
          break;
        }
      }
      drop = Drop(pane.id, before: before);
    } else {
      // Held by its middle, and set down on whole cells.
      final w = item.w.roundToDouble().clamp(1, pane.columns).toDouble();
      final h = item.h.roundToDouble().clamp(1, Pane.maxRows).toDouble();
      final cell = metrics.cellAt(
        at - Offset(metrics.across(w) / 2, metrics.down(h) / 2),
      );
      drop = Drop(
        pane.id,
        x: cell.dx.roundToDouble().clamp(0, pane.columns - w).toDouble(),
        y: cell.dy.roundToDouble().clamp(0, 999).toDouble(),
      );
    }

    // Where that puts it is asked of the layout itself, so the marker and
    // the result cannot disagree.
    final after = findPane(
      dropItem(layout, item, drop, panel: dragged.panel),
      pane.id,
    )!.pane;
    final index = after.items.indexWhere((other) => other.id == item.id);
    final rect = metrics.rectOf(
      placeItems(after.items, after.columns, after.mode)[index],
    );
    return (
      drop: drop,
      marker: MatrixUtils.transformRect(grid.getTransformTo(screen), rect),
    );
  }

  void _mark(Rect? marker) {
    if (marker != _marker) setState(() => _marker = marker);
  }

  Widget _tile(Entry entry) {
    final item = entry.item;
    Dragged dragged(String label, Widget picture) =>
        Dragged(item: item, placed: true, label: label, picture: picture);
    switch (entry) {
      case PaneEntry(:final view):
        final pane = view.pane;
        return KeyedSubtree(
          key: _boxes.putIfAbsent(pane.id, GlobalKey.new),
          child: DragHandle(
            data: dragged(
              pane.title.isEmpty ? 'Pane' : pane.title,
              const SymbolArt(Icons.dashboard_outlined),
            ),
            // Outlined, so that a pane with no background can be seen and
            // picked up by any part of it.
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: PaneBox(view: view, tile: _tile),
            ),
          ),
        );
      case CardEntry(:final card):
        return DragHandle(
          data: dragged(card.label, CardArt(card: card, padding: 4)),
          // The tile's own taps and holds are the remote's; absorbed, not
          // ignored, so that the drag starts where the tile is touched.
          child: AbsorbPointer(
            child: ArtTile(
              label: card.label,
              art: CardArt(card: card),
              bare: CardArt.isBare(card),
              showLabel: !item.hideName,
              boxStyle: item.style,
              onSelect: () {},
            ),
          ),
        );
      case PanelEntry():
        return DragHandle(
          data: dragged(entry.label, FolderArt(entry: entry)),
          child: AbsorbPointer(
            child: ArtTile(
              label: entry.label,
              art: FolderArt(entry: entry),
              bare: FolderArt.isBare(entry),
              showLabel: !item.hideName,
              boxStyle: item.style,
              onSelect: () {},
            ),
          ),
        );
      case WidgetEntry():
        final label = WidgetKind.named(item.ref)?.label ?? item.ref;
        return DragHandle(
          data: dragged(label, const SymbolArt(Icons.widgets_outlined)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: item.style.isEmpty ? Colors.white10 : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: StyledBox(
              style: item.style,
              radius: 10,
              padding: const EdgeInsets.all(8),
              child: Center(child: Text(label, textAlign: TextAlign.center)),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final home = resolveLayout(state.cards, state.config).home.root;
    return PaneFrame(
      wrap: _frame,
      child: DragTarget<Dragged>(
        onMove: (details) =>
            _mark(_target(details.offset, details.data)?.marker),
        onLeave: (_) => _mark(null),
        onAcceptWithDetails: (details) {
          final target = _target(details.offset, details.data);
          _mark(null);
          if (target != null) {
            placeDragged(context, ref, details.data, target.drop);
          }
        },
        builder: (context, _, _) => Container(
          key: _screen,
          width: Stage.size.width,
          height: Stage.size.height,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(color: Colors.black),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (state.wallpaper case final wallpaper?)
                Image(image: pictureAt(wallpaper), fit: BoxFit.cover),
              const ColoredBox(color: Color(0x73000000)),
              SingleChildScrollView(
                padding: EdgeInsets.all(home.pane.padding ?? 0),
                child: PaneGrid(view: home, tile: _tile),
              ),
              if (_marker case final marker?)
                Positioned.fromRect(
                  rect: marker,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.lightBlueAccent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
