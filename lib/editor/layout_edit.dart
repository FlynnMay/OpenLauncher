import 'dart:math';

import 'package:openlauncher/core/layout/layout.dart';

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

/// A pane with its panel and depth (a panel's root is 1).
typedef FoundPane = ({Panel panel, Component pane, int depth});

FoundPane? findPane(Layout layout, String id) {
  FoundPane? inside(Panel panel, Component pane, int depth) {
    if (pane.id == id) return (panel: panel, pane: pane, depth: depth);
    for (final inner in pane.children) {
      if (!inner.isPane) continue;
      if (inside(panel, inner, depth + 1) case final found?) return found;
    }
    return null;
  }

  for (final panel in layout.panels) {
    if (inside(panel, panel.root, 1) case final found?) return found;
  }
  return null;
}

int _deepest(Component pane) =>
    1 +
    pane.children.fold(
      0,
      (most, inner) => inner.isPane ? max(most, _deepest(inner)) : most,
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
List<Component> settle(List<Component> items, int columns, {String? fixed}) {
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

Layout _rebuilt(
  Layout layout,
  List<Component> Function(Component pane, List<Component> items) change, {
  Set<String>? removed,
  Panel? added,
}) => Layout(
  inbox: layout.inbox,
  removed: removed ?? layout.removed,
  panels: [
    for (final panel in [...layout.panels, ?added])
      panel.withRoot(panel.root.rebuild(change)),
  ],
);

/// Moves or adds [item] at [drop]. [panel] is the new folder that comes with
/// it. The caller has checked [refusal].
Layout dropItem(Layout layout, Component item, Drop drop, {Panel? panel}) {
  final found = findPane(layout, drop.pane)!;
  final target = found.pane;
  final whole = target.mode != PaneMode.free;
  final columns = target.columns * 1.0;
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
          target.columns,
          fixed: drop.x == null ? null : item.id,
        );
      case PaneMode.free:
        // Below everything, when no position is given.
        final below = rowCount(placeItems(items, target.columns, target.mode))
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
    added: panel,
    // Placing an entity un-removes it.
    removed: {...layout.removed}..removeAll(item.handed),
  );
}

/// Removes [id] and its contents. Entities left unplaced are marked removed
/// so the TV does not re-add them.
Layout removeItem(Layout layout, String id) {
  final gone = <Component>[];
  final rest = _rebuilt(
    layout,
    (_, items) => [
      for (final item in items)
        if (item.id == id) ...[] else item,
    ],
  );
  for (final panel in layout.panels) {
    for (final item in panel.root.all) {
      if (item.id == id) gone.addAll(item.isPane ? item.contents : [item]);
    }
  }
  final placed = {
    for (final panel in rest.panels)
      for (final item in panel.items)
        if (item.isInstance) ...item.handed,
  };
  return Layout(
    inbox: rest.inbox,
    panels: rest.panels,
    removed: {
      ...rest.removed,
      for (final item in gone)
        if (item.isInstance)
          for (final source in item.handed)
            if (!placed.contains(source) && rest.panel(source) == null) source,
    },
  );
}

/// A component with its parent pane and panel.
typedef Found = ({Component item, Component parent, Panel panel});

/// The components [ids], in layout order; missing ids are skipped.
List<Found> findItems(Layout layout, Set<String> ids) => [
  for (final panel in layout.panels)
    for (final pane in panel.root.panes)
      for (final item in pane.children)
        if (ids.contains(item.id)) (item: item, parent: pane, panel: panel),
];

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
              final wide = fit(w ?? item.w, pane.columns * 1.0);
              return item.sized(
                wide,
                fit(h ?? item.h, Component.maxRows * 1.0),
                // Kept inside the pane's width.
                x: item.x?.clamp(0, pane.columns - wide).toDouble(),
                y: item.y,
              );
            }()
          else
            item,
      ];
      if (pane.mode == PaneMode.grid) {
        for (final item in items) {
          if (ids.contains(item.id)) {
            next = settle(next, pane.columns, fixed: item.id);
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
      ? settle(next, pane.columns, fixed: id)
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

/// Sets a pane option. `mode` and `columns` also re-place the children.
Component withRule(Component pane, String key, Object? value) => switch (key) {
  'mode' => withMode(pane, PaneMode.values.asNameMap()[value] ?? PaneMode.flow),
  'columns' => withColumns(
    pane,
    value is num ? value.toInt() : Component.defaultColumns,
  ),
  _ => pane.withOption(key, value == '' ? null : value),
};

Panel withPanelRule(Panel panel, String key, Object? value) => key == 'title'
    ? panel.copyWith(title: value is String ? value : '')
    : panel.withRule(key, value);

/// Changes [pane]'s mode, keeping children where they were as far as
/// possible.
Component withMode(Component pane, PaneMode mode) {
  // A row or column keeps its children in order.
  if (mode.inLine) return pane.withOption('mode', mode.name);
  final placed = placeItems(pane.children, pane.columns, pane.mode);
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
        children: mode == PaneMode.grid ? settle(items, pane.columns) : items,
      );
}

/// Sets the column count, refitting what no longer fits.
Component withColumns(Component pane, int columns) {
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

Layout changePanel(Layout layout, String id, Panel Function(Panel) change) =>
    Layout(
      inbox: layout.inbox,
      removed: layout.removed,
      panels: [
        for (final panel in layout.panels)
          panel.id == id ? change(panel) : panel,
      ],
    );

/// Removes folder [id], its cards and its contents; entities left unplaced
/// are marked removed.
Layout removePanel(Layout layout, String id) {
  final panel = layout.panel(id);
  if (panel == null) return layout;
  final rest = _rebuilt(
    Layout(
      inbox: layout.inbox,
      removed: layout.removed,
      panels: [
        for (final other in layout.panels)
          if (other.id != id) other,
      ],
    ),
    (_, items) => [
      for (final item in items)
        // Its folder cards go with it.
        if (!item.isInstance || !item.handed.contains(id)) item,
    ],
  );
  final placed = placedCounts(rest);
  return Layout(
    inbox: rest.inbox,
    panels: rest.panels,
    removed: {
      ...rest.removed,
      for (final item in panel.items)
        if (item.isInstance)
          for (final source in item.handed)
            if (!placed.containsKey(source) && rest.panel(source) == null)
              source,
    },
  );
}

/// Adds an empty sidebar on edge [id] if there is none.
Layout withBar(Layout layout, String id) => layout.panel(id) != null
    ? layout
    : Layout(
        inbox: layout.inbox,
        removed: layout.removed,
        panels: [...layout.panels, Panel.empty(id)],
      );

/// Edges with no sidebar, or an empty one.
List<String> freeEdges(Layout layout) => [
  for (final id in Layout.barIds)
    if (layout.panel(id)?.root.children.isEmpty ?? true) id,
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
  for (final id in among) {
    final away = switch (Panel.edgeOf(id)) {
      BarEdge.left => x,
      BarEdge.right => width - x,
      BarEdge.top => y,
      BarEdge.bottom => height - y,
      null => double.infinity,
    };
    if (away <= least) {
      nearest = id;
      least = away;
    }
  }
  return nearest;
}

Layout withInbox(Layout layout, String paneId) =>
    Layout(inbox: paneId, removed: layout.removed, panels: layout.panels);

/// How many times each entity is placed.
Map<String, int> placedCounts(Layout layout) {
  final counts = <String, int>{};
  for (final panel in layout.panels) {
    for (final item in panel.items) {
      if (!item.isInstance) continue;
      for (final source in item.handed) {
        counts[source] = (counts[source] ?? 0) + 1;
      }
    }
  }
  return counts;
}
