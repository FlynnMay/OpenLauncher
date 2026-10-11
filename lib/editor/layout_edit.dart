import 'dart:math';

import 'package:openlauncher/core/layout/layout.dart';

/// Where in the layout something is put: into [pane], and there in front of
/// the item [before] (a pane that flows), or at the cell [x], [y] (a pane
/// with places). With neither, wherever there is room.
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

/// A pane, the panel it is on and how deep it is there; the pane that fills
/// a panel is at depth 1.
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

/// Why [item] cannot go into the pane [paneId], or null if it can. Only a
/// pane is ever refused.
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

/// Gives every one of [items], in a [PaneMode.grid] pane [columns] wide, a
/// cell of its own. [fixed], if given, gets exactly the cell it asks for;
/// the others keep theirs when they can and otherwise take the nearest free
/// one, or the first if they asked for none.
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

/// [layout] with [item] put where [drop] says, and taken from wherever it
/// was before if it was anywhere. [panel] is a new popup that comes with it,
/// when the item is an entity that opens one. The caller has made sure that
/// [refusal] has nothing against it.
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
        // With nowhere asked for, under everything that is there.
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
    // An entity that is placed is no longer one the user took off.
    removed: {...layout.removed}..remove(item.source),
  );
}

/// [layout] without the item [id] and whatever is in it. Entities that are then
/// on no panel are noted as removed, so the TV does not put them back as if
/// they were new apps.
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
        if (item.isInstance) ?item.source,
  };
  return Layout(
    inbox: rest.inbox,
    panels: rest.panels,
    removed: {
      ...rest.removed,
      for (final item in gone)
        if (item.source case final source?
            when item.isInstance &&
                !placed.contains(source) &&
                rest.panel(source) == null)
          source,
    },
  );
}

/// An item of the layout with where it is: the pane it is in and the panel
/// that pane is on.
typedef Found = ({Component item, Component parent, Panel panel});

/// The items [ids] name, in the order they are in [layout]; ids of things
/// that are no longer there are left out.
List<Found> findItems(Layout layout, Set<String> ids) => [
  for (final panel in layout.panels)
    for (final pane in panel.root.panes)
      for (final item in pane.children)
        if (ids.contains(item.id)) (item: item, parent: pane, panel: panel),
];

/// [layout] with each of the items [ids] replaced by what [change] makes of
/// it, given the pane it is in.
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

/// [layout] with the items [ids] made [w] cells wide and [h] tall; either
/// may be left as it is. In a pane with cells, what is then in the way of
/// one of them moves aside.
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

/// [layout] with the item [id] made [w] by [h] cells and, in a pane where
/// things have places, put at [x], [y]. In a pane with cells, what is then
/// in its way moves aside.
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

/// [layout] with one part of the transform of the items [ids] set: [key]
/// is `w`, `h`, `x`, `y`, `flex` or `aspect`, as a component saves them. A place is a column and
/// a row together, so setting one of them where there was neither starts
/// the other at nought, and taking one away ([value] null) takes both.
Layout transformItems(
  Layout layout,
  Set<String> ids,
  String key,
  double? value,
) => switch (key) {
  // In a line: a share of the room, or a shape. None is said as nought.
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

/// [pane] with the rule called [key] set to [value], as it is saved; null
/// for the usual. How it places things and how many columns it has take
/// what is in it with them.
Component withRule(Component pane, String key, Object? value) => switch (key) {
  'mode' => withMode(pane, PaneMode.values.asNameMap()[value] ?? PaneMode.flow),
  'columns' => withColumns(
    pane,
    value is num ? value.toInt() : Component.defaultColumns,
  ),
  _ => pane.withOption(key, value == '' ? null : value),
};

/// The same for a panel: a sidebar's rules, a folder's.
Panel withPanelRule(Panel panel, String key, Object? value) => key == 'title'
    ? panel.copyWith(title: value is String ? value : '')
    : panel.withRule(key, value);

/// [pane] placing its items the [mode] way, each staying where it was as
/// far as that way allows.
Component withMode(Component pane, PaneMode mode) {
  // A line keeps what is in it as it is, in the order it was.
  if (mode.inLine) return pane.withOption('mode', mode.name);
  final placed = placeItems(pane.children, pane.columns, pane.mode);
  final whole = mode != PaneMode.free;
  double size(double value) => whole ? max(1.0, value.roundToDouble()) : value;
  final List<Component> items;
  if (mode == PaneMode.flow) {
    // In reading order of where they were.
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

/// [pane] with [columns] cells across; what no longer fits is made to.
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

/// [layout] with the panel [id] replaced by what [change] makes of it.
Layout changePanel(Layout layout, String id, Panel Function(Panel) change) =>
    Layout(
      inbox: layout.inbox,
      removed: layout.removed,
      panels: [
        for (final panel in layout.panels)
          panel.id == id ? change(panel) : panel,
      ],
    );

/// [layout] without the popup [id], the entities that open it, and what was in
/// it; entities that are then nowhere are noted as removed.
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
        // What opened it has nothing left to open.
        if (!item.isInstance || item.source != id) item,
    ],
  );
  final placed = placedCounts(rest);
  return Layout(
    inbox: rest.inbox,
    panels: rest.panels,
    removed: {
      ...rest.removed,
      for (final item in panel.items)
        if (item.source case final source?
            when item.isInstance &&
                !placed.containsKey(source) &&
                rest.panel(source) == null)
          source,
    },
  );
}

/// [layout] with a sidebar on the edge [id] names, empty if there was none.
Layout withBar(Layout layout, String id) => layout.panel(id) != null
    ? layout
    : Layout(
        inbox: layout.inbox,
        removed: layout.removed,
        panels: [...layout.panels, Panel.empty(id)],
      );

/// The edges, by sidebar id, that have no sidebar: none was ever put
/// there, or the one that was has nothing in it.
List<String> freeEdges(Layout layout) => [
  for (final id in Layout.barIds)
    if (layout.panel(id)?.root.children.isEmpty ?? true) id,
];

/// The edge [among] those given that the point ([x], [y]) is nearest to on
/// a screen [width] by [height], if it is within [reach] of one.
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

/// [layout] with new apps going to the pane [paneId].
Layout withInbox(Layout layout, String paneId) =>
    Layout(inbox: paneId, removed: layout.removed, panels: layout.panels);

/// How many times each entity is somewhere in [layout], by entity id.
Map<String, int> placedCounts(Layout layout) {
  final counts = <String, int>{};
  for (final panel in layout.panels) {
    for (final item in panel.items) {
      if (item.source case final source? when item.isInstance) {
        counts[source] = (counts[source] ?? 0) + 1;
      }
    }
  }
  return counts;
}
