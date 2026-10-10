import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/after_frame.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layer_stack.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/resize_handles.dart';
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

  /// The one thing picked out, if it is somewhere its cells can be found:
  /// where it is on the screen, and what is needed to work out a new size
  /// for it from how far a handle is dragged.
  ({Found found, Placement placed, PaneMetrics metrics, Rect rect})? _picked() {
    final layout = ref.read(configProvider).value?.layout;
    final ids = ref.read(selectionProvider);
    if (layout == null || ids.length != 1) return null;
    final found = findItems(layout, ids).singleOrNull;
    final grid = _box(_grids[found?.parent.id]), screen = _box(_screen);
    if (found == null || grid == null || screen == null) return null;
    final pane = found.parent;
    final placed = placeItems(
      pane.items,
      pane.columns,
      pane.mode,
    )[pane.items.indexOf(found.item)];
    final metrics = PaneMetrics(pane, grid.size.width);
    return (
      found: found,
      placed: placed,
      metrics: metrics,
      rect: MatrixUtils.transformRect(
        grid.getTransformTo(screen),
        metrics.rectOf(placed),
      ),
    );
  }

  /// The handles that can do something for a thing placed at [placed] in
  /// [pane]: an edge has one if it can go outwards, there being room in the
  /// pane, or inwards, the thing being more than a cell across; a corner
  /// has one if both its edges do.
  static Set<ResizeHandle> _handles(Placement placed, Pane pane) {
    bool across(int side) =>
        side == 0 ||
        placed.w > 1 ||
        (side < 0 ? placed.x > 0 : placed.x + placed.w < pane.columns);
    bool down(int side) =>
        side == 0 ||
        placed.h > 1 ||
        (side < 0 ? placed.y > 0 : placed.h < Pane.maxRows);
    return {
      for (final handle in ResizeHandle.values)
        if (across(handle.dx) && down(handle.dy)) handle,
    };
  }

  /// What the layout would be with the handle let go where it is, shown
  /// by the marker until it is.
  Layout? _resized;

  /// Works out, in whole cells, the size and place the picked-out thing
  /// has with [handle] dragged [moved] from where it was taken hold of.
  void _resize(ResizeHandle handle, Offset moved) {
    final picked = _picked();
    final layout = ref.read(configProvider).value?.layout;
    if (picked == null || layout == null) return;
    final (:found, :placed, :metrics, rect: _) = picked;
    final pane = found.parent;
    final columns = metrics.cellAt(moved).dx.round();
    final rows = metrics.cellAt(moved).dy.round();
    // An edge can go no further than leaves one cell, or than the pane.
    final left = handle.dx < 0
        ? (placed.x + columns).clamp(0, placed.x + placed.w - 1)
        : placed.x;
    final top = handle.dy < 0
        ? (placed.y + rows).clamp(0, placed.y + placed.h - 1)
        : placed.y;
    final right = handle.dx > 0
        ? (placed.x + placed.w + columns).clamp(left + 1, pane.columns)
        : placed.x + placed.w;
    final bottom = handle.dy > 0
        ? (placed.y + placed.h + rows).clamp(top + 1, top + Pane.maxRows)
        : placed.y + placed.h;
    // Where things flow there is no place to keep or change, only a size:
    // any handle pulled outwards makes it bigger by that much.
    final flows = pane.mode == PaneMode.flow;
    final next = reshapeItem(
      layout,
      found.item.id,
      x: left * 1.0,
      y: top * 1.0,
      w: flows
          ? (placed.w + handle.dx * columns).clamp(1, pane.columns) * 1.0
          : (right - left) * 1.0,
      h: flows
          ? (placed.h + handle.dy * rows).clamp(1, Pane.maxRows) * 1.0
          : (bottom - top) * 1.0,
    );
    final grid = _box(_grids[pane.id]), screen = _box(_screen);
    final after = findItems(next, {found.item.id}).single;
    if (grid == null || screen == null) return;
    setState(() {
      _resized = next;
      // Asked of the layout, as a drop is, so that what is shown is what
      // letting go gives.
      _marker = MatrixUtils.transformRect(
        grid.getTransformTo(screen),
        metrics.rectOf(
          placeItems(
            after.parent.items,
            after.parent.columns,
            after.parent.mode,
          )[after.parent.items.indexOf(after.item)],
        ),
      );
    });
  }

  void _resizeDone({required bool kept}) {
    final next = _resized;
    setState(() {
      _resized = null;
      _marker = null;
    });
    if (kept && next != null) changeLayout(context, ref, (_) => next);
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
              if (editing)
                Positioned.fill(
                  child: LayerStack(navigator: TvScreen.navigator),
                ),
              if (editing)
                Positioned.fill(
                  child: AfterFrame(
                    read: _picked,
                    same: (a, b) =>
                        a?.rect == b?.rect &&
                        a?.found.item.id == b?.found.item.id &&
                        a?.found.parent.mode == b?.found.parent.mode,
                    builder: (context, picked) => Stack(
                      children: [
                        if (picked != null)
                          ResizeHandles(
                            // While one is held, around where it would be.
                            rect: _resized == null
                                ? picked.rect
                                : _marker ?? picked.rect,
                            handles: _handles(
                              picked.placed,
                              picked.found.parent,
                            ),
                            onDragged: _resize,
                            onDone: _resizeDone,
                          ),
                      ],
                    ),
                  ),
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
