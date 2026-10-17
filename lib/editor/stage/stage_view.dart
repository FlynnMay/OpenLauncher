import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/stage/layer_stack.dart';
import 'package:openlauncher/editor/stage/prefab_screen.dart';
import 'package:openlauncher/editor/stage/resize_handles.dart';
import 'package:openlauncher/editor/stage/snapping.dart';
import 'package:openlauncher/editor/stage/stage_geometry.dart';
import 'package:openlauncher/editor/stage/tv_screen.dart';
import 'package:openlauncher/features/home/docked_node.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';

/// The TV's screen, or the open prefab on it. While [editing], components are
/// selectable and draggable and the screen is a drop target; otherwise it is
/// the plain launcher.
class Stage extends ConsumerStatefulWidget {
  const Stage({super.key, required this.editing});

  final bool editing;

  @override
  ConsumerState<Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<Stage> {
  final _screen = GlobalKey();

  /// Keys for each container's grid, and for the box of each nested container
  /// and of each child of a row or column.
  final _grids = <String, GlobalKey>{}, _boxes = <String, GlobalKey>{};

  /// What is being edited: each component's parent container, by id.
  var _parents = const <String, Node>{};

  /// Where the dragged thing would land.
  Rect? _marker;

  /// The docked container being dragged over.
  String? _over;

  static RenderBox? _box(GlobalKey? key) =>
      switch (key?.currentContext?.findRenderObject()) {
        final RenderBox box when box.attached && box.hasSize => box,
        _ => null,
      };

  /// A slot's grid goes by the node holding what is put in it.
  Widget _grid(Node container, Widget grid) => KeyedSubtree(
    key: _grids.putIfAbsent(
      container.slotHolder ?? container.id,
      GlobalKey.new,
    ),
    child: grid,
  );

  Widget _plainTile(Node item, Widget tile) => tile;

  Widget _editTile(Node item, Widget tile) {
    // A part of an instance is not a thing of its own.
    final parent = _parents[item.id];
    if (parent == null) return tile;
    // A prefab's root stays where it is.
    final fixed = item.id == ref.read(editedPrefabProvider)?.root.id;
    Widget handle(String label, Widget picture, Widget child) => fixed
        ? child
        : DragHandle(
            data: Dragged(
              item: item,
              placed: true,
              label: label,
              picture: picture,
            ),
            child: child,
          );
    // In a row or column its box is what a drop goes before or after.
    Widget boxed(Widget child) => item.isContainer || parent.mode.inLine
        ? KeyedSubtree(
            key: _boxes.putIfAbsent(item.id, GlobalKey.new),
            child: child,
          )
        : child;
    // Absorbs the tile's own gestures so a tap or drag starts on it.
    final still = _Selectable(
      id: item.id,
      child: AbsorbPointer(child: tile),
    );
    if (item.isContainer) {
      return boxed(
        handle(
          item.name.isEmpty ? 'Layout' : item.name,
          const SymbolArt(Icons.dashboard_outlined),
          // Outlined so a container with no background can be seen and grabbed.
          _Selectable(
            id: item.id,
            shape: shapeOf(item),
            resting: Colors.white24,
            child: tile,
          ),
        ),
      );
    }
    if (!item.isInstance) {
      return boxed(
        handle(
          item.visual?.label ?? 'Node',
          const SymbolArt(Icons.widgets_outlined),
          still,
        ),
      );
    }
    final source = item.handed.firstOrNull ?? '';
    final entity = ref.read(entitiesProvider).value?.byId(source);
    return boxed(
      entity != null
          ? handle(entity.label, EntityArt(entity: entity, padding: 4), still)
          : handle(
              source.isEmpty ? 'Prefab' : source,
              NodeArt(node: source),
              still,
            ),
    );
  }

  /// The drop for [dragged] at [pointer] and its marker rect; null where
  /// nothing accepts it.
  ({Drop? drop, String? bar, Rect marker})? _target(
    Offset pointer,
    Dragged dragged,
  ) {
    final layout = ref.read(editedLayoutProvider);
    if (layout == null) return null;
    if (dragged.docking) {
      // A new docked container only goes to a free edge.
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
    // The last docked container showing under the pointer, else the home
    // screen.
    var container = layout.home.root;
    String? bar;
    for (final dock in layout.docked) {
      // What an instance holds goes in its slot.
      final into = dock.isInstance ? dock.children.firstOrNull : dock;
      final grid = _grids[into?.id];
      if (into == null || _box(grid) == null) continue;
      final showing = grid?.currentContext
          ?.getInheritedWidgetOfExactType<FocusBounds>()
          ?.visible();
      if (showing?.contains(pointer) ?? false) {
        container = into;
        bar = dock.id;
      }
    }
    // A docked container dragged over opens.
    if (bar != _over) setState(() => _over = bar);
    // The innermost container under the pointer, excluding the dragged one.
    for (Node? inner = container; inner != null;) {
      container = inner;
      inner = null;
      for (final other in container.children) {
        final box = other.isContainer ? _box(_boxes[other.id]) : null;
        if (other.id != item.id &&
            box != null &&
            (Offset.zero & box.size).contains(box.globalToLocal(pointer))) {
          inner = other;
        }
      }
    }
    if (whyNot(ref, dragged, container.id) != null) return null;
    final screen = _box(_screen);
    if (screen == null) return null;
    if (container.mode.inLine) return _inLine(container, pointer, item, screen);
    final grid = _box(_grids[container.id]);
    if (grid == null) return null;

    final metrics = CellMetrics(container, grid.size.width);
    final drop = dropAt(
      container,
      metrics,
      grid.size,
      grid.globalToLocal(pointer),
      item,
      stepIn(container, snap: ref.read(snapProvider)),
    );

    // The marker is computed from the resulting layout so it cannot disagree
    // with it.
    final after = findContainer(
      dropItem(layout, item, drop, opens: dragged.opens),
      container.id,
    )!.container;
    final rect = rectIn(after, item.id, metrics, grid.size);
    return (
      drop: drop,
      bar: null,
      marker: MatrixUtils.transformRect(grid.getTransformTo(screen), rect),
    );
  }

  /// The drop for [item] at [pointer] in the row or column [container]: before
  /// the first child whose middle is past the pointer. The marker is a bar
  /// between the two.
  ({Drop? drop, String? bar, Rect marker})? _inLine(
    Node container,
    Offset pointer,
    Node item,
    RenderBox screen,
  ) {
    final box = _box(_boxes[container.id]);
    if (box == null) return null;
    Rect on(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(screen),
      Offset.zero & box.size,
    );
    final row = container.mode == LayoutMode.row;
    final at = screen.globalToLocal(pointer);
    final whole = on(box);
    const thick = 4.0;
    String? before;
    // Where the bar goes along the line: the start, or after the last child.
    var along = row ? whole.left : whole.top;
    for (final child in container.children) {
      final rect = switch (child.id == item.id
          ? null
          : _box(_boxes[child.id])) {
        null => null,
        final box => on(box),
      };
      if (rect == null) continue;
      if (row ? at.dx < rect.center.dx : at.dy < rect.center.dy) {
        before = child.id;
        along = ((row ? rect.left : rect.top) + along) / 2;
        break;
      }
      along = row ? rect.right : rect.bottom;
    }
    return (
      drop: Drop(container.id, before: before),
      bar: null,
      marker: row
          ? Rect.fromLTWH(along - thick / 2, whole.top, thick, whole.height)
          : Rect.fromLTWH(whole.left, along - thick / 2, whole.width, thick),
    );
  }

  /// The single selected node, if its place can be found: its rect and what
  /// resizing needs.
  ({Found found, Placement placed, CellMetrics metrics, Rect rect, Size size})?
  _picked() {
    final layout = ref.read(editedLayoutProvider);
    final ids = ref.read(selectionProvider);
    if (layout == null || ids.length != 1) return null;
    final found = findItems(layout, ids).singleOrNull;
    final grid = _box(_grids[found?.parent.id]), screen = _box(_screen);
    if (found == null || grid == null || screen == null) return null;
    final container = found.parent;
    final placed = placementIn(container, found.item.id);
    final metrics = CellMetrics(container, grid.size.width);
    return (
      found: found,
      placed: placed,
      metrics: metrics,
      size: grid.size,
      rect: MatrixUtils.transformRect(
        grid.getTransformTo(screen),
        rectIn(container, found.item.id, metrics, grid.size),
      ),
    );
  }

  /// The layout as it would be on release, shown by the marker.
  Layout? _resized;

  /// The new size and position for [handle] dragged by [moved].
  void _resize(ResizeHandle handle, Offset moved) {
    final picked = _picked();
    final layout = ref.read(editedLayoutProvider);
    if (picked == null || layout == null) return;
    final (:found, :placed, :metrics, :size, rect: _) = picked;
    final container = found.parent;
    final grid = _box(_grids[container.id]), screen = _box(_screen);
    if (grid == null || screen == null) return;
    // In the container's own pixels, which a prefab's are enlarged from.
    final by = moved / grid.getTransformTo(screen).getMaxScaleOnAxis();
    final step = stepIn(container, snap: ref.read(snapProvider));
    final Layout next;
    if (container.mode == LayoutMode.free) {
      next = placeItem(
        layout,
        found.item.id,
        resizedRect(found.item.transform.rectIn(size), handle, by, step),
        size,
      );
    } else {
      final to = resizedTo(container, placed, metrics, handle, by, step);
      next = reshapeItem(
        layout,
        found.item.id,
        x: to.x,
        y: to.y,
        w: to.w,
        h: to.h,
      );
    }
    final after = findItems(next, {found.item.id}).single;
    setState(() {
      _resized = next;
      // Computed from the resulting layout, as for a drop.
      _marker = MatrixUtils.transformRect(
        grid.getTransformTo(screen),
        rectIn(after.parent, after.item.id, metrics, size),
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
    final layout = ref.watch(editedLayoutProvider);
    final prefab = ref.watch(editedPrefabProvider) != null;
    _parents = {
      for (final container in layout?.all ?? const <Node>[])
        for (final child in container.children) child.id: container,
    };
    // The frames stay mounted so toggling editing keeps the launcher's state.
    final screen = LayoutFrame(
      wrap: _grid,
      child: TileFrame(
        wrap: editing ? _editTile : _plainTile,
        still: editing,
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
              addBar(context, ref, bar, details.data.docks!);
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
                child: prefab ? const PrefabScreen() : const TvScreen(),
              ),
              if (editing && !prefab)
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
                            ),
                            onDragged: _resize,
                            onDone: _resizeDone,
                          ),
                      ],
                    ),
                  ),
                ),
              // While a new docked container is dragged, the edges that would
              // take it.
              if (layout != null &&
                  !prefab &&
                  held.any((dragged) => dragged?.docking ?? false))
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
    return DockHold(
      // Open while edited, while something in it is selected or dragged over
      // it.
      ids: {
        // Released while previewing its opening.
        if (editing && !ref.watch(barReplayProvider)) ...{
          ?_over,
          for (final one in ref.watch(selectedProvider)) ...[
            if (one.item.isDocked) one.item.id,
            ?one.dock?.id,
          ],
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
