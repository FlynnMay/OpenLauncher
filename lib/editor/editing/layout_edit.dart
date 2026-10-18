import 'dart:math';
import 'dart:ui';

import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/docked_prefabs.dart';

/// A drop target: [container], and either before child [before] (in order), at
/// cell [x], [y] (a grid) or covering [rect] of a container of [size] (no
/// layout). With none, wherever there is room.
class Drop {
  const Drop(
    this.container, {
    this.before,
    this.x,
    this.y,
    this.rect,
    this.size,
  });

  final String container;
  final String? before;
  final double? x, y;
  final Rect? rect;
  final Size? size;

  @override
  bool operator ==(Object other) =>
      other is Drop &&
      other.container == container &&
      other.before == before &&
      other.x == x &&
      other.y == y &&
      other.rect == rect &&
      other.size == size;

  @override
  int get hashCode => Object.hash(container, before, x, y, rect, size);
}

/// [item] moved to cover [rect] of a parent of [size]: anchored as it was,
/// or pinned to the top left if it filled its last one.
Node placedAt(Node item, Rect rect, Size size) => item.copyWith(
  transform: item.transform.isFill
      ? NodeTransform.at(rect)
      : item.transform.covering(rect, size),
);

/// [item] anchored at [x] and [y] (each axis's min and max) in a parent of
/// [size], staying where it is.
Node withAnchors(
  Node item,
  (double, double) x,
  (double, double) y,
  Size size,
) => item.copyWith(
  transform: NodeTransform(
    minX: x.$1,
    maxX: x.$2,
    minY: y.$1,
    maxY: y.$2,
  ).covering(item.transform.rectIn(size), size),
);

/// A container with its screen, the docked container it is or is in (if any),
/// and its depth counted from that, or from the screen's root (1).
typedef FoundContainer = ({
  Screen screen,
  Node container,
  Node? dock,
  int depth,
});

/// An instance's id finds the node holding its first slot.
FoundContainer? findContainer(Layout layout, String id) {
  FoundContainer? inside(Screen screen, Node container, Node? dock, int depth) {
    if (container.offCells) (dock, depth) = (container, 1);
    if (container.id == id && container.isInstance) {
      return switch (container.children.firstOrNull) {
        final holder? => (
          screen: screen,
          container: holder,
          dock: dock,
          depth: depth,
        ),
        null => null,
      };
    }
    if (container.id == id) {
      return (screen: screen, container: container, dock: dock, depth: depth);
    }
    for (final inner in container.children) {
      // What an instance holds is as deep as the instance.
      final deeper = container.isInstance ? depth : depth + 1;
      if (inside(screen, inner, dock, deeper) case final found?) return found;
    }
    return null;
  }

  for (final screen in layout.screens) {
    if (inside(screen, screen.root, null, 1) case final found?) return found;
  }
  return null;
}

int _deepest(Node container) =>
    1 +
    container.children.fold(
      0,
      (most, inner) => inner.isContainer && !inner.offCells
          ? max(most, _deepest(inner))
          : most,
    );

/// Why [item] cannot go into [containerId], or null. Only containers are ever
/// refused.
String? refusal(Layout layout, Node item, String containerId) {
  final found = findContainer(layout, containerId);
  if (found == null) return 'That layout is gone.';
  if (!item.isContainer) return null;
  if (item.containers.any((container) => container.id == containerId)) {
    return 'A layout cannot go inside itself.';
  }
  if (found.depth + _deepest(item) > Node.maxDepth) {
    return 'Layouts can be nested ${Node.maxDepth - 1} deep.';
  }
  return null;
}

/// Gives each of [items] its own cell in a grid container. [fixed] gets exactly
/// the cell it asks for; the rest keep theirs or take the nearest free one.
///
/// Docked containers take no cells and are left as they are.
List<Node> settle(List<Node> items, int columns, {String? fixed}) {
  if (items.any((item) => item.offCells)) {
    final rest = settle(
      [
        for (final item in items)
          if (!item.offCells) item,
      ],
      columns,
      fixed: fixed,
    ).iterator;
    return [
      for (final item in items)
        item.offCells ? item : (rest..moveNext()).current,
    ];
  }
  final taken = <(int, int)>{};
  final settled = <String, Node>{};
  int wide(Node item) => item.w.round().clamp(1, columns);
  int tall(Node item) => max(1, item.h.round());
  bool free(Node item, int x, int y) {
    if (x < 0 || y < 0 || x + wide(item) > columns) return false;
    for (var row = y; row < y + tall(item); row++) {
      for (var column = x; column < x + wide(item); column++) {
        if (taken.contains((column, row))) return false;
      }
    }
    return true;
  }

  void take(Node item, int x, int y) {
    for (var row = y; row < y + tall(item); row++) {
      for (var column = x; column < x + wide(item); column++) {
        taken.add((column, row));
      }
    }
    settled[item.id] = item.sized(
      wide(item) * 1.0,
      tall(item) * 1.0,
      x: x * 1.0,
      y: y * 1.0,
    );
  }

  for (final item in items) {
    if (item.id != fixed) continue;
    take(
      item,
      (item.x?.round() ?? 0).clamp(0, columns - wide(item)),
      max(0, item.y?.round() ?? 0),
    );
  }
  final homeless = <Node>[];
  for (final item in items) {
    if (settled.containsKey(item.id)) continue;
    final x = item.x?.round(), y = item.y?.round();
    if (x != null && y != null && free(item, x, y)) {
      take(item, x, y);
    } else {
      homeless.add(item);
    }
  }
  for (final item in homeless) {
    final picky = item.x != null && item.y != null;
    final wantX = item.x?.round() ?? 0, wantY = item.y?.round() ?? 0;
    ({int x, int y, int distance})? best;
    for (var y = 0; best == null || y <= best.y + best.distance; y++) {
      for (var x = 0; x + wide(item) <= columns; x++) {
        if (!free(item, x, y)) continue;
        final distance = picky
            ? (x - wantX).abs() + (y - wantY).abs()
            : y * columns + x;
        if (best == null || distance < best.distance) {
          best = (x: x, y: y, distance: distance);
        }
      }
      // With no wish, the first free place in reading order will do.
      if (!picky && best != null) break;
    }
    take(item, best.x, best.y);
  }
  return [for (final item in items) settled[item.id]!];
}

/// [layout] with every container's children changed, and [added] (a new docked
/// container) put on the home screen.
Layout _rebuilt(
  Layout layout,
  List<Node> Function(Node container, List<Node> items) change, {
  Set<String>? removed,
  Node? added,
}) {
  final next = layout.rebuild(change, removed: removed);
  return added == null
      ? next
      : next.withContainer(
          next.home.root.id,
          (root) => root.copyWith(children: [...root.children, added]),
        );
}

/// Moves or adds [item] at [drop]. [opens] is the new docked container it
/// opens. The caller has checked [refusal].
Layout dropItem(Layout layout, Node item, Drop drop, {Node? opens}) {
  final found = findContainer(layout, drop.container)!;
  final target = found.container;
  final columns = target.reach * 1.0;
  final w = min(max(1.0, item.w.roundToDouble()), columns);
  final h = item.h.roundToDouble().clamp(1.0, SizingModule.maxRows * 1.0);

  List<Node> into(List<Node> items) {
    switch (target.mode) {
      case LayoutMode.flow:
        final index = items.indexWhere((other) => other.id == drop.before);
        return [...items]
          ..insert(index < 0 ? items.length : index, item.sized(w, h));
      // A line takes it as it is, in its turn.
      case LayoutMode.row || LayoutMode.column:
        final index = items.indexWhere((other) => other.id == drop.before);
        return [...items]..insert(index < 0 ? items.length : index, item);
      case LayoutMode.grid:
        return settle(
          [...items, item.sized(w, h, x: drop.x, y: drop.y)],
          target.reach,
          fixed: drop.x == null ? null : item.id,
        );
      case LayoutMode.free:
        // At the top left, when no place is given.
        return [
          ...items,
          switch ((drop.rect, drop.size)) {
            (final rect?, final size?) => placedAt(item, rect, size),
            _ => item.copyWith(
              transform: NodeTransform.at(const Rect.fromLTWH(0, 0, 160, 90)),
            ),
          },
        ];
    }
  }

  return _rebuilt(
    layout,
    (container, items) {
      final rest = [
        for (final other in items)
          if (other.id != item.id) other,
      ];
      return container.id == target.id ? into(rest) : rest;
    },
    added: opens,
    // Placing an entity un-removes it.
    removed: {...layout.removed}..removeAll(item.handed),
  );
}

/// Removes [id] and its contents, and the instances handed it.
/// Entities left unplaced are marked removed so the TV does not re-add them.
Layout removeItem(Layout layout, String id) {
  final gone = [
    for (final item in layout.all)
      if (item.id == id) ...[if (!item.isContainer) item, ...item.contents],
  ];
  final handed = layout.node(id) != null;
  final rest = _rebuilt(
    layout,
    (_, items) => [
      for (final item in items)
        if (item.id != id &&
            !(handed && item.isInstance && item.handed.contains(id)))
          item,
    ],
  );
  final placed = placedCounts(rest);
  return rest.copyWith(
    removed: {
      ...rest.removed,
      for (final item in gone)
        if (item.isInstance)
          for (final source in item.handed)
            // A node is not an entity to put back.
            if (!placed.containsKey(source) && rest.node(source) == null)
              source,
    },
  );
}

/// A component with its parent container, its screen and the docked container it
/// is in, if any.
typedef Found = ({Node item, Node parent, Screen screen, Node? dock});

/// The components [ids], in layout order; missing ids are skipped.
List<Found> findItems(Layout layout, Set<String> ids) {
  final found = <Found>[];
  void under(Screen screen, Node container, Node? dock) {
    final inside = container.offCells ? container : dock;
    for (final item in container.children) {
      if (ids.contains(item.id)) {
        found.add((
          item: item,
          parent: container,
          screen: screen,
          dock: inside,
        ));
      }
    }
    for (final item in container.children) {
      if (!item.isInstance) under(screen, item, inside);
      // What an instance holds is found in the node holding its slot.
      if (item.isInstance) {
        for (final holder in item.children) {
          under(screen, holder, item.offCells ? item : inside);
        }
      }
    }
  }

  for (final screen in layout.screens) {
    under(screen, screen.root, null);
  }
  return found;
}

/// Replaces each of [ids] with what [change] returns.
Layout changeItems(
  Layout layout,
  Set<String> ids,
  Node Function(Node item, Node parent) change,
) => _rebuilt(
  layout,
  (container, items) => [
    for (final item in items)
      ids.contains(item.id) ? change(item, container) : item,
  ],
);

/// Resizes [ids]. In a grid container, whatever is in the way moves aside.
Layout resizeItems(Layout layout, Set<String> ids, {double? w, double? h}) =>
    _rebuilt(layout, (container, items) {
      double fit(double value, double most) =>
          value.roundToDouble().clamp(1, most);
      var next = [
        for (final item in items)
          if (ids.contains(item.id))
            () {
              final wide = fit(w ?? item.w, container.reach * 1.0);
              return item.sized(
                wide,
                fit(h ?? item.h, SizingModule.maxRows * 1.0),
                // Kept inside the container's width.
                x: item.x?.clamp(0, container.reach - wide).toDouble(),
                y: item.y,
              );
            }()
          else
            item,
      ];
      if (container.mode == LayoutMode.grid) {
        for (final item in items) {
          if (ids.contains(item.id)) {
            next = settle(next, container.reach, fixed: item.id);
          }
        }
      }
      return next;
    });

/// Resizes and repositions [id]. In a grid container, whatever is in the way
/// moves aside.
Layout reshapeItem(
  Layout layout,
  String id, {
  required double w,
  required double h,
  double? x,
  double? y,
}) => _rebuilt(layout, (container, items) {
  if (!items.any((item) => item.id == id)) return items;
  final flows = container.mode == LayoutMode.flow;
  final next = [
    for (final item in items)
      if (item.id == id)
        item.sized(
          w,
          h,
          x: flows ? null : x ?? item.x,
          y: flows ? null : y ?? item.y,
        )
      else
        item,
  ];
  return container.mode == LayoutMode.grid
      ? settle(next, container.reach, fixed: id)
      : next;
});

/// Moves [id] to cover [rect] of its parent, of [size], which has no layout.
Layout placeItem(Layout layout, String id, Rect rect, Size size) => changeItems(
  layout,
  {id},
  (item, parent) =>
      parent.mode == LayoutMode.free ? placedAt(item, rect, size) : item,
);

/// Sets one Sizing field (`w`, `h`, `x`, `y`, `flex`, `aspect`) on [ids].
/// Setting x or y alone starts the other at 0; clearing one clears both.
Layout transformItems(
  Layout layout,
  Set<String> ids,
  String key,
  double? value,
) => switch (key) {
  // 0 means none.
  'flex' || 'aspect' => changeItems(
    layout,
    ids,
    (item, _) => item.withValue(sizingModule.name, key, value ?? 0),
  ),
  'w' => resizeItems(layout, ids, w: value),
  'h' => resizeItems(layout, ids, h: value),
  _ when value == null => changeItems(
    layout,
    ids,
    (item, _) => item.sized(item.w, item.h),
  ),
  _ => findItems(layout, ids).fold(
    layout,
    (layout, found) => reshapeItem(
      layout,
      found.item.id,
      w: found.item.w,
      h: found.item.h,
      x: key == 'x' ? value : found.item.x ?? 0,
      y: key == 'y' ? value : found.item.y ?? 0,
    ),
  ),
};

/// Sets [key] of [module] on [container]. `mode` and `columns` also place the
/// children; `position` docks or undocks it.
Node withRule(Node container, String module, String key, Object? value) =>
    switch ((module, key)) {
      ('layout', 'mode') => withMode(
        container,
        LayoutMode.values.asNameMap()[value] ?? LayoutMode.flow,
      ),
      ('layout', 'columns') => withColumns(
        container,
        value is num ? value.toInt() : LayoutModule.defaultColumns,
      ),
      ('dock', 'position') => withDock(
        container,
        value is String ? value : null,
      ),
      // No longer scrolling across, its children go back inside its columns.
      ('scroll', 'across') when value != true && !container.mode.inLine =>
        withColumns(container.withValue(module, key, null), container.columns),
      ('dock', 'width' || 'height') when value == DockModule.fill =>
        container.withValue(module, key, 'fill'),
      _ => container.withValue(module, key, value == '' ? null : value),
    };

/// Docks [container] at [dock], or with null puts it back on its parent's
/// cells.
Node withDock(Node container, String? dock) {
  if (dock != null) {
    return container.withValue(dockModule.name, 'position', dock);
  }
  // Showing and hiding go with the dock, unless it is an Overlay.
  if (container.isOverlay) return container.withModule(dockModule.name, null);
  return container.withModule(dockModule.name, null).triggered({
    for (final MapEntry(:key, :value) in container.on.entries)
      if (key == Trigger.press || key == Trigger.hold) key: value,
  });
}

/// Changes [container]'s mode, keeping children where they were as far as
/// possible.
Node withMode(Node container, LayoutMode mode) {
  final laid = container.withValue(layoutModule.name, 'mode', mode.name);
  // A row or column keeps its children in order.
  if (mode.inLine) return laid;
  // Without a layout before, in reading order of where they were.
  final placed = container.mode != LayoutMode.free
      ? placeItems(container.children, container.reach, container.mode)
      : [
          for (final child in container.children)
            switch (child.transform.rectIn(const Size(960, 540))) {
              final rect => Placement(rect.left, rect.top, 1, 1),
            },
        ];
  double size(double value) => max(1.0, value.roundToDouble());
  final List<Node> items;
  if (mode == LayoutMode.flow) {
    // In reading order of their old positions.
    final order = [for (var i = 0; i < placed.length; i++) i]
      ..sort((a, b) {
        final rows = placed[a].y.compareTo(placed[b].y);
        return rows != 0 ? rows : placed[a].x.compareTo(placed[b].x);
      });
    items = [
      for (final index in order)
        container.children[index].sized(
          size(container.children[index].w),
          size(container.children[index].h),
        ),
    ];
  } else {
    items = [
      for (final (index, item) in container.children.indexed)
        item.sized(
          size(item.w),
          size(item.h),
          x: container.mode == LayoutMode.free ? null : placed[index].x,
          y: container.mode == LayoutMode.free ? null : placed[index].y,
        ),
    ];
  }
  return laid.copyWith(
    children: mode == LayoutMode.grid ? settle(items, laid.reach) : items,
  );
}

/// Sets the column count, refitting what no longer fits.
Node withColumns(Node container, int columns) {
  // Nothing is past the end of one that scrolls across.
  final set = container.withValue(layoutModule.name, 'columns', columns);
  if (container.scrollsAcross) return set;
  final items = [
    for (final item in container.children)
      () {
        final w = min(item.w, columns * 1.0);
        return item.sized(
          w,
          item.h,
          x: item.x?.clamp(0, columns - w).toDouble(),
          y: item.y,
        );
      }(),
  ];
  return set.copyWith(
    children: container.mode == LayoutMode.grid
        ? settle(items, columns)
        : items,
  );
}

/// The screen edges a container can dock to.
const barEdges = ['left', 'right', 'top', 'bottom'];

/// The container docked to [edge], if any.
Node? barOn(Layout layout, String edge) =>
    layout.docked.where((container) => container.dock == edge).firstOrNull;

/// Adds an instance of [prefab] docked to [edge], if none is.
Layout withBar(Layout layout, String edge, Prefab prefab) =>
    barOn(layout, edge) != null
    ? layout
    : layout.withContainer(
        layout.home.root.id,
        (root) => root.copyWith(
          children: [
            ...root.children,
            dockedInstance(prefab, layout.containerIdFor(edge), dock: edge),
          ],
        ),
      );

/// Edges with no container docked, or an empty one.
List<String> freeEdges(Layout layout) => [
  for (final edge in barEdges)
    if (barOn(layout, edge)?.isEmpty ?? true) edge,
];

/// The edge of [among] nearest to ([x], [y]), if within [reach].
String? edgeNear(
  double x,
  double y,
  double width,
  double height,
  Iterable<String> among, {
  double reach = 90,
}) {
  String? nearest;
  var least = reach;
  for (final edge in among) {
    final away = switch (edge) {
      'left' => x,
      'right' => width - x,
      'top' => y,
      'bottom' => height - y,
      _ => double.infinity,
    };
    if (away <= least) {
      nearest = edge;
      least = away;
    }
  }
  return nearest;
}

Layout withInbox(Layout layout, String containerId) =>
    layout.copyWith(inbox: containerId);

/// How many times each entity is placed.
Map<String, int> placedCounts(Layout layout) {
  final counts = <String, int>{};
  for (final item in layout.items) {
    if (!item.isInstance) continue;
    for (final source in item.handed) {
      counts[source] = (counts[source] ?? 0) + 1;
    }
  }
  return counts;
}

/// [item] with [on] as its triggers, and the Focus module that a press or a
/// hold needs to be felt.
Node withPressable(Node item, Triggers on) {
  // Kept when it has none, so the module stays.
  final next = item.withModule(triggersModule.name, triggersToJson(on));
  final presses = [
    Trigger.press,
    Trigger.hold,
  ].any((trigger) => on[trigger]?.isNotEmpty ?? false);
  return presses && !next.added(focusModule.name)
      ? next.withModule(focusModule.name, const {})
      : next;
}
