import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/after_frame.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layer_stack.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/resize_handles.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/snapping.dart';
import 'package:openlauncher/editor/stage_geometry.dart';
import 'package:openlauncher/editor/tv_screen.dart';
import 'package:openlauncher/features/home/component_view.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/sidebar.dart';

/// The TV's screen. While [editing], components are selectable and draggable
/// and the screen is a drop target; otherwise it is the plain launcher.
class Stage extends ConsumerStatefulWidget {
  const Stage({super.key, required this.editing});

  final bool editing;

  @override
  ConsumerState<Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<Stage> {
  final _screen = GlobalKey();

  /// Keys for each pane's grid and each nested pane's box.
  final _grids = <String, GlobalKey>{}, _boxes = <String, GlobalKey>{};

  /// Where the dragged thing would land.
  Rect? _marker;

  /// The sidebar being dragged over.
  String? _over;

  static RenderBox? _box(GlobalKey? key) =>
      switch (key?.currentContext?.findRenderObject()) {
        final RenderBox box when box.attached && box.hasSize => box,
        _ => null,
      };

  Widget _grid(Component pane, Widget grid) => KeyedSubtree(
    key: _grids.putIfAbsent(pane.id, GlobalKey.new),
    child: grid,
  );

  Widget _plainTile(Component item, Widget tile) => tile;

  Widget _editTile(Component item, Widget tile) {
    Dragged dragged(String label, Widget picture) =>
        Dragged(item: item, placed: true, label: label, picture: picture);
    // Absorbs the tile's own gestures so a tap or drag starts on it.
    final still = _Selectable(
      id: item.id,
      child: AbsorbPointer(child: tile),
    );
    if (item.isPane) {
      return KeyedSubtree(
        key: _boxes.putIfAbsent(item.id, GlobalKey.new),
        child: DragHandle(
          data: dragged(
            item.title.isEmpty ? 'Pane' : item.title,
            const SymbolArt(Icons.dashboard_outlined),
          ),
          // Outlined so a pane with no background can be seen and grabbed.
          child: _Selectable(
            id: item.id,
            shape: PaneBox.shapeOf(item),
            resting: Colors.white24,
            child: tile,
          ),
        ),
      );
    }
    if (!item.isInstance) {
      return DragHandle(
        data: dragged(
          ComponentKind.named(item.kind)?.label ?? item.kind,
          const SymbolArt(Icons.widgets_outlined),
        ),
        child: still,
      );
    }
    final source = item.handed.firstOrNull ?? '';
    final entity = ref.read(entitiesProvider).value?.byId(source);
    return DragHandle(
      data: entity != null
          ? dragged(entity.label, EntityArt(entity: entity, padding: 4))
          : dragged(
              source.isEmpty ? 'Prefab' : source,
              FolderArt(folder: source),
            ),
      child: still,
    );
  }

  /// The drop for [dragged] at [pointer] and its marker rect; null where
  /// nothing accepts it.
  ({Drop? drop, String? bar, Rect marker})? _target(
    Offset pointer,
    Dragged dragged,
  ) {
    final layout = ref.read(configProvider).value?.layout;
    if (layout == null) return null;
    if (dragged.sidebar) {
      // A sidebar only goes to a free edge.
      final screen = _box(_screen);
      if (screen == null) return null;
      final at = screen.globalToLocal(pointer);
      final edge = edgeNear(
        at.dx,
        at.dy,
        screen.size.width,
        screen.size.height,
        freeEdges(layout),
      );
      if (edge == null) return null;
      return (drop: null, bar: edge, marker: barRect(layout, edge));
    }
    final item = dragged.item;
    // An open popup is the only target; else a visible sidebar; else the home
    // screen.
    var pane = layout.home.root;
    String? bar;
    for (final panel in layout.panels) {
      final grid = _grids[panel.root.id];
      if (_box(grid) == null) continue;
      if (panel.kind == PanelKind.popup) {
        pane = panel.root;
        bar = null;
        break;
      }
      final showing = grid?.currentContext
          ?.getInheritedWidgetOfExactType<FocusBounds>()
          ?.visible();
      if (panel.kind == PanelKind.sidebar &&
          (showing?.contains(pointer) ?? false)) {
        pane = panel.root;
        bar = panel.id;
      }
    }
    // A sidebar dragged over opens.
    if (bar != _over) setState(() => _over = bar);
    // The innermost pane under the pointer, excluding the dragged one.
    for (Component? inner = pane; inner != null;) {
      pane = inner;
      inner = null;
      for (final other in pane.children) {
        final box = other.isPane ? _box(_boxes[other.id]) : null;
        if (other.id != item.id &&
            box != null &&
            (Offset.zero & box.size).contains(box.globalToLocal(pointer))) {
          inner = other;
        }
      }
    }
    final grid = _box(_grids[pane.id]), screen = _box(_screen);
    if (grid == null || screen == null) return null;
    if (refusal(layout, item, pane.id) != null) return null;

    final metrics = PaneMetrics(pane, grid.size.width);
    final drop = dropAt(
      pane,
      metrics,
      grid.globalToLocal(pointer),
      item,
      stepIn(pane, snap: ref.read(snapProvider)),
    );

    // The marker is computed from the resulting layout so it cannot disagree
    // with it.
    final after = findPane(
      dropItem(layout, item, drop, panel: dragged.panel),
      pane.id,
    )!.pane;
    final rect = metrics.rectOf(placementIn(after, item.id));
    return (
      drop: drop,
      bar: null,
      marker: MatrixUtils.transformRect(grid.getTransformTo(screen), rect),
    );
  }

  /// The single selected component, if its cells can be found: its rect and
  /// what resizing needs.
  ({Found found, Placement placed, PaneMetrics metrics, Rect rect})? _picked() {
    final layout = ref.read(configProvider).value?.layout;
    final ids = ref.read(selectionProvider);
    if (layout == null || ids.length != 1) return null;
    final found = findItems(layout, ids).singleOrNull;
    final grid = _box(_grids[found?.parent.id]), screen = _box(_screen);
    if (found == null || grid == null || screen == null) return null;
    final pane = found.parent;
    final placed = placementIn(pane, found.item.id);
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

  /// The layout as it would be on release, shown by the marker.
  Layout? _resized;

  /// The new size and position for [handle] dragged by [moved].
  void _resize(ResizeHandle handle, Offset moved) {
    final picked = _picked();
    final layout = ref.read(configProvider).value?.layout;
    if (picked == null || layout == null) return;
    final (:found, :placed, :metrics, rect: _) = picked;
    final pane = found.parent;
    final to = resizedTo(
      pane,
      placed,
      metrics,
      handle,
      moved,
      stepIn(pane, snap: ref.read(snapProvider)),
    );
    final next = reshapeItem(
      layout,
      found.item.id,
      x: to.x,
      y: to.y,
      w: to.w,
      h: to.h,
    );
    final grid = _box(_grids[pane.id]), screen = _box(_screen);
    final after = findItems(next, {found.item.id}).single;
    if (grid == null || screen == null) return;
    setState(() {
      _resized = next;
      // Computed from the resulting layout, as for a drop.
      _marker = MatrixUtils.transformRect(
        grid.getTransformTo(screen),
        metrics.rectOf(placementIn(after.parent, after.item.id)),
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
    // The frames stay mounted so toggling editing keeps the launcher's state.
    final screen = PaneFrame(
      wrap: _grid,
      child: TileFrame(
        wrap: editing ? _editTile : _plainTile,
        child: DragTarget<Dragged>(
          onWillAcceptWithDetails: (_) => editing,
          onMove: (details) =>
              _mark(_target(details.offset, details.data)?.marker),
          onLeave: (_) {
            _mark(null);
            if (_over != null) setState(() => _over = null);
          },
          onAcceptWithDetails: (details) {
            final target = _target(details.offset, details.data);
            _mark(null);
            if (_over != null) setState(() => _over = null);
            if (target?.bar case final bar?) {
              addBar(context, ref, bar);
            } else if (target?.drop case final drop?) {
              placeDragged(context, ref, details.data, drop);
            }
          },
          builder: (context, held, _) => Stack(
            key: _screen,
            children: [
              // Tapping empty space clears the selection.
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
                            // While resizing, around the new rect.
                            rect: _resized == null
                                ? picked.rect
                                : _marker ?? picked.rect,
                            handles: resizeHandles(
                              picked.found.item,
                              picked.placed,
                              picked.found.parent,
                              leastSpan(
                                stepIn(
                                  picked.found.parent,
                                  snap: ref.watch(snapProvider),
                                ),
                              ),
                            ),
                            onDragged: _resize,
                            onDone: _resizeDone,
                          ),
                      ],
                    ),
                  ),
                ),
              // While a sidebar is dragged, the edges that would take it.
              if (ref.read(configProvider).value?.layout case final layout?
                  when held.any((dragged) => dragged?.sidebar ?? false))
                for (final id in freeEdges(layout))
                  Positioned.fromRect(
                    rect: barRect(layout, id, thickness: 8),
                    child: const IgnorePointer(
                      child: ColoredBox(color: Color(0x9940C4FF)),
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
    return SidebarHold(
      // Open while edited, while something in it is selected or dragged over
      // it.
      ids: {
        // Released while previewing its opening.
        if (editing && !ref.watch(barReplayProvider)) ...{
          ?ref.watch(barProvider),
          ?_over,
          for (final one in ref.watch(selectedProvider))
            if (one.panel.kind == PanelKind.sidebar) one.panel.id,
        },
      },
      child: screen,
    );
  }
}

/// A tap selects it; with Ctrl/Shift or multi-select it toggles. Selected
/// things are outlined.
class _Selectable extends ConsumerWidget {
  const _Selectable({
    required this.id,
    required this.child,
    this.shape = const BorderRadius.all(Radius.circular(10)),
    this.resting,
  });

  final String id;
  final Widget child;
  final BorderRadius shape;

  /// Outline when not selected.
  final Color? resting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      selectionProvider.select((ids) => ids.contains(id)),
    );
    final outline = selected ? Colors.lightBlueAccent : resting;
    return GestureDetector(
      onTap: () => ref.read(selectionProvider.notifier).press(id),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: outline == null
              ? null
              : Border.all(color: outline, width: selected ? 2 : 1),
        ),
        child: child,
      ),
    );
  }
}
