import 'dart:math';

import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/templates.dart';

/// A drop target: [pane], and either before child [before] (flow) or at cell
/// [x], [y]. With neither, wherever there is room.
class Drop {
  const Drop(this.pane, {this.before, this.x, this.y});

  final String pane;
  final String? before;
  final double? x, y;

  @override
  bool operator ==(Object other) =>
      other is Drop &&
      other.pane == pane &&
      other.before == before &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(pane, before, x, y);
}

/// A pane with its layer, the docked pane it is or is in (if any), and its
/// depth counted from that, or from the layer's root (1).
typedef FoundPane = ({Layer layer, Component pane, Component? dock, int depth});

FoundPane? findPane(Layout layout, String id) {
  FoundPane? inside(Layer layer, Component pane, Component? dock, int depth) {
    if (pane.isDocked) (dock, depth) = (pane, 1);
    if (pane.id == id) {
      return (layer: layer, pane: pane, dock: dock, depth: depth);
    }
    for (final inner in pane.children) {
      if (!inner.isPane) continue;
      if (inside(layer, inner, dock, depth + 1) case final found?) return found;
    }
    return null;
  }

  for (final layer in layout.layers) {
    if (inside(layer, layer.root, null, 1) case final found?) return found;
  }
  return null;
}

int _deepest(Component pane) =>
    1 +
    pane.children.fold(
      0,
      (most, inner) =>
          inner.isPane && !inner.isDocked ? max(most, _deepest(inner)) : most,
    );

/// Why [item] cannot go into [paneId], or null. Only panes are ever refused.
String? refusal(Layout layout, Component item, String paneId) {
  final found = findPane(layout, paneId);
  if (found == null) return 'That pane is gone.';
  if (!item.isPane) return null;
  if (item.panes.any((pane) => pane.id == paneId)) {
    return 'A pane cannot go inside itself.';
  }
  if (found.depth + _deepest(item) > Component.maxDepth) {
    return 'Panes can be nested ${Component.maxDepth - 1} deep.';
  }
  return null;
}

/// Gives each of [items] its own cell in a grid pane. [fixed] gets exactly
/// the cell it asks for; the rest keep theirs or take the nearest free one.
///
/// Docked panes take no cells and are left as they are.
List<Component> settle(List<Component> items, int columns, {String? fixed}) {
  if (items.any((item) => item.isDocked)) {
    final rest = settle(
      [
        for (final item in items)
          if (!item.isDocked) item,
      ],
      columns,
      fixed: fixed,
    ).iterator;
    return [
      for (final item in items)
        item.isDocked ? item : (rest..moveNext()).current,
    ];
  }
  final taken = <(int, int)>{};
  final settled = <String, Component>{};
  int wide(Component item) => item.w.round().clamp(1, columns);
  int tall(Component item) => max(1, item.h.round());
  bool free(Component item, int x, int y) {
    if (x < 0 || y < 0 || x + wide(item) > columns) return false;
    for (var row = y; row < y + tall(item); row++) {
      for (var column = x; column < x + wide(item); column++) {
        if (taken.contains((column, row))) return false;
      }
    }
    return true;
  }

  void take(Component item, int x, int y) {
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
  final homeless = <Component>[];
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

/// [layout] with every pane's children changed, and [added] (a new folder)
/// put on the home layer.
Layout _rebuilt(
  Layout layout,
  List<Component> Function(Component pane, List<Component> items) change, {
  Set<String>? removed,
  Component? added,
}) {
  final next = layout.rebuild(change, removed: removed);
  return added == null
      ? next
      : next.withPane(
          next.home.root.id,
          (root) => root.copyWith(children: [...root.children, added]),
        );
}

/// Moves or adds [item] at [drop]. [folder] is the new folder that comes with
/// it. The caller has checked [refusal].
Layout dropItem(Layout layout, Component item, Drop drop, {Component? folder}) {
  final found = findPane(layout, drop.pane)!;
  final target = found.pane;
  final whole = target.mode != PaneMode.free;
  final columns = target.reach * 1.0;
  final w = min(whole ? max(1.0, item.w.roundToDouble()) : item.w, columns);
  final h = whole
      ? item.h.roundToDouble().clamp(1.0, Component.maxRows * 1.0)
      : item.h;

  List<Component> into(List<Component> items) {
    switch (target.mode) {
      case PaneMode.flow:
        final index = items.indexWhere((other) => other.id == drop.before);
        return [...items]
          ..insert(index < 0 ? items.length : index, item.sized(w, h));
      // A line takes it as it is, in its turn.
      case PaneMode.row || PaneMode.column:
        final index = items.indexWhere((other) => other.id == drop.before);
        return [...items]..insert(index < 0 ? items.length : index, item);
      case PaneMode.grid:
        return settle(
          [...items, item.sized(w, h, x: drop.x, y: drop.y)],
          target.reach,
          fixed: drop.x == null ? null : item.id,
        );
      case PaneMode.free:
        // Below everything, when no position is given.
        final below = rowCount(placeItems(items, target.reach, target.mode))
            .ceilToDouble();
        return [
          ...items,
          item.sized(
            w,
            h,
            x: (drop.x ?? 0).clamp(0, columns - w).toDouble(),
            y: max(0, drop.y ?? below),
          ),
        ];
    }
  }

  return _rebuilt(
    layout,
    (pane, items) {
      final rest = [
        for (final other in items)
          if (other.id != item.id) other,
      ];
      return pane.id == target.id ? into(rest) : rest;
    },
    added: folder,
    // Placing an entity un-removes it.
    removed: {...layout.removed}..removeAll(item.handed),
  );
}

/// Removes [id] and its contents, and with a folder the cards that open it.
/// Entities left unplaced are marked removed so the TV does not re-add them.
Layout removeItem(Layout layout, String id) {
  final gone = [
    for (final item in layout.all)
      if (item.id == id) ...item.isPane ? item.contents : [item],
  ];
  final docked = layout.pane(id)?.isDocked ?? false;
  final rest = _rebuilt(
    layout,
    (_, items) => [
      for (final item in items)
        if (item.id != id &&
            !(docked && item.isInstance && item.handed.contains(id)))
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
            // A folder is not an entity to put back.
            if (!placed.containsKey(source) && rest.pane(source) == null)
              source,
    },
  );
}

/// A component with its parent pane, its layer and the docked pane it is in,
/// if any.
typedef Found = ({
  Component item,
  Component parent,
  Layer layer,
  Component? dock,
});

/// The components [ids], in layout order; missing ids are skipped.
List<Found> findItems(Layout layout, Set<String> ids) {
  final found = <Found>[];
  void under(Layer layer, Component pane, Component? dock) {
    final inside = pane.isDocked ? pane : dock;
    for (final item in pane.children) {
      if (ids.contains(item.id)) {
        found.add((item: item, parent: pane, layer: layer, dock: inside));
      }
    }
    for (final item in pane.children) {
      if (item.isPane) under(layer, item, inside);
    }
  }

  for (final layer in layout.layers) {
    under(layer, layer.root, null);
  }
  return found;
}

/// Replaces each of [ids] with what [change] returns.
Layout changeItems(
  Layout layout,
  Set<String> ids,
  Component Function(Component item, Component parent) change,
) => _rebuilt(
  layout,
  (pane, items) => [
    for (final item in items) ids.contains(item.id) ? change(item, pane) : item,
  ],
);

/// Resizes [ids]. In a grid pane, whatever is in the way moves aside.
Layout resizeItems(Layout layout, Set<String> ids, {double? w, double? h}) =>
    _rebuilt(layout, (pane, items) {
      final whole = pane.mode != PaneMode.free;
      final least = whole ? 1.0 : Component.minFreeSpan;
      double fit(double value, double most) =>
          (whole ? value.roundToDouble() : value).clamp(least, most);
      var next = [
        for (final item in items)
          if (ids.contains(item.id))
            () {
              final wide = fit(w ?? item.w, pane.reach * 1.0);
              return item.sized(
                wide,
                fit(h ?? item.h, Component.maxRows * 1.0),
                // Kept inside the pane's width.
                x: item.x?.clamp(0, pane.reach - wide).toDouble(),
                y: item.y,
              );
            }()
          else
            item,
      ];
      if (pane.mode == PaneMode.grid) {
        for (final item in items) {
          if (ids.contains(item.id)) {
            next = settle(next, pane.reach, fixed: item.id);
          }
        }
      }
      return next;
    });

/// Resizes and repositions [id]. In a grid pane, whatever is in the way moves
/// aside.
Layout reshapeItem(
  Layout layout,
  String id, {
  required double w,
  required double h,
  double? x,
  double? y,
}) => _rebuilt(layout, (pane, items) {
  if (!items.any((item) => item.id == id)) return items;
  final flows = pane.mode == PaneMode.flow;
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
  return pane.mode == PaneMode.grid
      ? settle(next, pane.reach, fixed: id)
      : next;
});

/// Sets one transform field (`w`, `h`, `x`, `y`, `flex`, `aspect`) on [ids].
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
    (item, _) => item.overridden({
      'transform': {key: value ?? 0},
    }),
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

/// Sets a pane option. `mode` and `columns` also re-place the children; a
/// new dock takes what docking adds from the templates in [prefabs].
Component withRule(
  Component pane,
  String key,
  Object? value, {
  Map<String, Prefab> prefabs = const {},
}) => switch (key) {
  'mode' => withMode(pane, PaneMode.values.asNameMap()[value] ?? PaneMode.flow),
  'columns' => withColumns(
    pane,
    value is num ? value.toInt() : Component.defaultColumns,
  ),
  'dock' => withDock(pane, value is String ? value : null, prefabs),
  // No longer scrolling across, its children go back inside its columns.
  'scrollX' when value != true && !pane.mode.inLine => withColumns(
    pane.withOption(key, null),
    pane.columns,
  ),
  'width' ||
  'height' when value == Component.fill => pane.withOption(key, 'fill'),
  _ => pane.withOption(key, value == '' ? null : value),
};

/// Docks [pane] at [dock], or with null puts it back on its parent's cells.
Component withDock(
  Component pane,
  String? dock, [
  Map<String, Prefab> prefabs = const {},
]) {
  // What only a docked pane has goes with the dock.
  if (dock == null) {
    return pane.copyWith(
      options: {
        for (final MapEntry(:key, :value) in pane.options.entries)
          if (!dockKeys.contains(key)) key: value,
      },
      on: {
        for (final MapEntry(:key, :value) in pane.on.entries)
          if (key == Trigger.press || key == Trigger.hold) key: value,
      },
    );
  }
  // Newly docked, it is a sidebar.
  if (!pane.isDocked) {
    return dockedLike(
      pane,
      sidebarFrom(templateFor(dock, prefabs), pane.id, dock),
    );
  }
  // A folder moved into what opens it needs no layer; moved out, it does.
  if (pane.hovers &&
      (dock == Component.inline) != (pane.dock == Component.inline)) {
    return pane
        .withOption('dock', dock)
        .copyWith(
          on: {
            for (final MapEntry(:key, :value) in pane.on.entries)
              if (key != Trigger.reveal && key != Trigger.hide) key: value,
            if (dock != Component.inline)
              for (final MapEntry(:key, :value) in folderFrom(
                templateFor(dock, prefabs),
                pane.id,
              ).on.entries)
                if (key == Trigger.reveal || key == Trigger.hide) key: value,
          },
        );
  }
  return pane.withOption('dock', dock);
}

/// Changes [pane]'s mode, keeping children where they were as far as
/// possible.
Component withMode(Component pane, PaneMode mode) {
  // A row or column keeps its children in order.
  if (mode.inLine) return pane.withOption('mode', mode.name);
  final placed = placeItems(pane.children, pane.reach, pane.mode);
  final whole = mode != PaneMode.free;
  double size(double value) => whole ? max(1.0, value.roundToDouble()) : value;
  final List<Component> items;
  if (mode == PaneMode.flow) {
    // In reading order of their old positions.
    final order = [for (var i = 0; i < placed.length; i++) i]
      ..sort((a, b) {
        final rows = placed[a].y.compareTo(placed[b].y);
        return rows != 0 ? rows : placed[a].x.compareTo(placed[b].x);
      });
    items = [
      for (final index in order)
        pane.children[index].sized(
          size(pane.children[index].w),
          size(pane.children[index].h),
        ),
    ];
  } else {
    double place(double value) => whole ? value.roundToDouble() : value;
    items = [
      for (final (index, item) in pane.children.indexed)
        item.sized(
          size(item.w),
          size(item.h),
          x: place(placed[index].x),
          y: place(placed[index].y),
        ),
    ];
  }
  return pane
      .withOption('mode', mode.name)
      .copyWith(
        children: mode == PaneMode.grid ? settle(items, pane.reach) : items,
      );
}

/// Sets the column count, refitting what no longer fits.
Component withColumns(Component pane, int columns) {
  // Nothing is past the end of one that scrolls across.
  if (pane.scrollsAcross) return pane.withOption('columns', columns);
  final items = [
    for (final item in pane.children)
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
  return pane
      .withOption('columns', columns)
      .copyWith(
        children: pane.mode == PaneMode.grid ? settle(items, columns) : items,
      );
}

/// The screen edges a sidebar can be on.
const barEdges = ['left', 'right', 'top', 'bottom'];

/// The sidebar on [edge], if any.
Component? barOn(Layout layout, String edge) => layout.docked
    .where((pane) => pane.dock == edge && !pane.hovers)
    .firstOrNull;

/// Adds an empty sidebar on [edge] made from [template] if there is none.
Layout withBar(Layout layout, String edge, [Prefab? template]) =>
    barOn(layout, edge) != null
    ? layout
    : layout.withPane(
        layout.home.root.id,
        (root) => root.copyWith(
          children: [
            ...root.children,
            sidebarFrom(template, layout.paneIdFor(edge), edge, layout.itemIds),
          ],
        ),
      );

/// Edges with no sidebar, or an empty one.
List<String> freeEdges(Layout layout) => [
  for (final edge in barEdges)
    if (barOn(layout, edge)?.children.isEmpty ?? true) edge,
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

Layout withInbox(Layout layout, String paneId) =>
    layout.copyWith(inbox: paneId);

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
