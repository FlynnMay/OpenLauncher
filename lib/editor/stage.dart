import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/popup_panel.dart';

/// The launcher itself, running in a box the size of the TV's screen: the
/// same home screen, popups, menus and settings, each kept inside the box.
class TvScreen extends StatelessWidget {
  const TvScreen({super.key});

  /// The TV's screen, in the units everything on it is measured in.
  static const size = Size(960, 540);

  /// The launcher's own navigator, for opening something on its screen
  /// from outside it.
  static final navigator = GlobalKey<NavigatorState>();

  /// Shows the popup [panelId] on the launcher's screen.
  static void openPopup(String panelId) {
    if (navigator.currentState?.overlay?.context case final context?) {
      showPanelPopup(context, panelId);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: size,
        padding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
      ),
      child: ClipRect(
        // Its own, so that what the launcher opens and says stays on its
        // screen instead of covering the page.
        child: ScaffoldMessenger(
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          ),
        ),
      ),
    ),
  );
}

/// The TV's screen with, while [editing], everything on it something to
/// pick up and move rather than to open, and the screen itself somewhere to
/// drop things. Otherwise it is simply the launcher, to be used.
class Stage extends ConsumerStatefulWidget {
  const Stage({super.key, required this.editing});

  final bool editing;

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

  Widget _grid(Pane pane, Widget grid) => KeyedSubtree(
    key: _grids.putIfAbsent(pane.id, GlobalKey.new),
    child: grid,
  );

  Widget _plainTile(Entry entry, Widget tile) => tile;

  Widget _editTile(Entry entry, Widget tile) {
    Dragged dragged(String label, Widget picture) =>
        Dragged(item: entry.item, placed: true, label: label, picture: picture);
    // The tile's own taps and holds are the remote's; absorbed, not
    // ignored, so that a tap or a drag starts where the tile is touched.
    final still = _Selectable(
      id: entry.item.id,
      child: AbsorbPointer(child: tile),
    );
    switch (entry) {
      case PaneEntry(view: PaneView(:final pane)):
        return KeyedSubtree(
          key: _boxes.putIfAbsent(pane.id, GlobalKey.new),
          child: DragHandle(
            data: dragged(
              pane.title.isEmpty ? 'Pane' : pane.title,
              const SymbolArt(Icons.dashboard_outlined),
            ),
            // Outlined, so that a pane with no background can be seen and
            // picked up or picked out by any part of it.
            child: _Selectable(
              id: entry.item.id,
              radius: 14,
              resting: Colors.white24,
              child: tile,
            ),
          ),
        );
      case CardEntry(:final card):
        return DragHandle(
          data: dragged(card.label, CardArt(card: card, padding: 4)),
          child: still,
        );
      case PanelEntry():
        return DragHandle(
          data: dragged(entry.label, FolderArt(entry: entry)),
          child: still,
        );
      case WidgetEntry(:final item):
        return DragHandle(
          data: dragged(
            WidgetKind.named(item.ref)?.label ?? item.ref,
            const SymbolArt(Icons.widgets_outlined),
          ),
          child: still,
        );
    }
  }

  /// Where [dragged] would go if let go of at [pointer], and where on the
  /// screen that is; null over nothing that would take it.
  ({Drop drop, Rect marker})? _target(Offset pointer, Dragged dragged) {
    final layout = ref.read(configProvider).value?.layout;
    if (layout == null) return null;
    final item = dragged.item;
    // An open popup is all there is to drop on; otherwise the home screen.
    var pane = layout.home.root;
    for (final panel in layout.panels) {
      if (panel.kind == PanelKind.popup &&
          _box(_grids[panel.root.id]) != null) {
        pane = panel.root;
      }
    }
    // The innermost pane under the pointer, other than the one dragged.
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    // The frames are always there, so that going in and out of editing
    // leaves the launcher as it was: the same screen, the same popup open.
    return PaneFrame(
      wrap: _grid,
      child: TileFrame(
        wrap: editing ? _editTile : _plainTile,
        child: DragTarget<Dragged>(
          onWillAcceptWithDetails: (_) => editing,
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
          builder: (context, _, _) => Stack(
            key: _screen,
            children: [
              // A tap on nothing lets go of what was picked out.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: editing
                    ? ref.read(selectionProvider.notifier).clear
                    : null,
                child: const TvScreen(),
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

/// Something on the screen that a tap picks out for editing: alone, or
/// together with what already is when Ctrl or Shift is held or several are
/// being picked. What is picked out is outlined.
class _Selectable extends ConsumerWidget {
  const _Selectable({
    required this.id,
    required this.child,
    this.radius = 10,
    this.resting,
  });

  final String id;
  final Widget child;
  final double radius;

  /// The outline it has while not picked out, if any.
  final Color? resting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      selectionProvider.select((ids) => ids.contains(id)),
    );
    final outline = selected ? Colors.lightBlueAccent : resting;
    return GestureDetector(
      onTap: () {
        final keys = HardwareKeyboard.instance;
        ref
            .read(selectionProvider.notifier)
            .tap(
              id,
              adding:
                  ref.read(selectSeveralProvider) ||
                  keys.isControlPressed ||
                  keys.isShiftPressed ||
                  keys.isMetaPressed,
            );
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: outline == null
              ? null
              : Border.all(color: outline, width: selected ? 2 : 1),
        ),
        child: child,
      ),
    );
  }
}
