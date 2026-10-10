import 'dart:math';

import 'package:openlauncher/core/layout/layout.dart';

final _random = Random();

/// An id nothing else has, starting with [prefix]: `i` for an item, `s` for
/// a pane, `p` for a popup, as the first config page wrote them.
String newId(String prefix) =>
    prefix +
    List.generate(7, (_) => _random.nextInt(36).toRadixString(36)).join();

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
typedef FoundPane = ({Panel panel, Pane pane, int depth});

FoundPane? findPane(Layout layout, String id) {
  FoundPane? inside(Panel panel, Pane pane, int depth) {
    if (pane.id == id) return (panel: panel, pane: pane, depth: depth);
    for (final item in pane.items) {
      if (item.pane case final inner?) {
        if (inside(panel, inner, depth + 1) case final found?) return found;
      }
    }
    return null;
  }

  for (final panel in layout.panels) {
    if (inside(panel, panel.root, 1) case final found?) return found;
  }
  return null;
}

int _deepest(Pane pane) =>
    1 +
    pane.items.fold(
      0,
      (most, item) => switch (item.pane) {
        null => most,
        final inner => max(most, _deepest(inner)),
      },
    );

/// Why [item] cannot go into the pane [paneId], or null if it can. Only a
/// pane is ever refused.
String? refusal(Layout layout, LayoutItem item, String paneId) {
  final found = findPane(layout, paneId);
  if (found == null) return 'That pane is gone.';
  final inner = item.pane;
  if (inner == null) return null;
  if (found.panel.kind == PanelKind.sidebar) {
    return 'A sidebar holds cards and widgets, not panes.';
  }
  if (inner.panes.any((pane) => pane.id == paneId)) {
    return 'A pane cannot go inside itself.';
  }
  if (found.depth + _deepest(inner) > Pane.maxDepth) {
    return 'Panes can be nested ${Pane.maxDepth - 1} deep.';
  }
  return null;
}

/// Gives every one of [items], in a [PaneMode.grid] pane [columns] wide, a
/// cell of its own. [fixed], if given, gets exactly the cell it asks for;
/// the others keep theirs when they can and otherwise take the nearest free
/// one, or the first if they asked for none.
List<LayoutItem> settle(List<LayoutItem> items, int columns, {String? fixed}) {
  final taken = <(int, int)>{};
  final settled = <String, LayoutItem>{};
  int wide(LayoutItem item) => item.w.round().clamp(1, columns);
  int tall(LayoutItem item) => max(1, item.h.round());
  bool free(LayoutItem item, int x, int y) {
    if (x < 0 || y < 0 || x + wide(item) > columns) return false;
    for (var row = y; row < y + tall(item); row++) {
      for (var column = x; column < x + wide(item); column++) {
        if (taken.contains((column, row))) return false;
      }
    }
    return true;
  }

  void take(LayoutItem item, int x, int y) {
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
  final homeless = <LayoutItem>[];
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
  List<LayoutItem> Function(Pane pane, List<LayoutItem> items) change, {
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
/// when the item is a card that opens one. The caller has made sure that
/// [refusal] has nothing against it.
Layout dropItem(Layout layout, LayoutItem item, Drop drop, {Panel? panel}) {
  final found = findPane(layout, drop.pane)!;
  final target = found.pane;
  final whole = target.mode != PaneMode.free;
  final columns = target.columns * 1.0;
  final w = min(whole ? max(1.0, item.w.roundToDouble()) : item.w, columns);
  final h =
      found.panel.kind == PanelKind.sidebar && item.kind != ItemKind.widget
      ? 1.0
      : whole
      ? item.h.roundToDouble().clamp(1.0, Pane.maxRows * 1.0)
      : item.h;

  List<LayoutItem> into(List<LayoutItem> items) {
    switch (target.mode) {
      case PaneMode.flow:
        final index = items.indexWhere((other) => other.id == drop.before);
        return [...items]
          ..insert(index < 0 ? items.length : index, item.sized(w, h));
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
    // A card that is placed is no longer one the user took off.
    removed: {...layout.removed}..remove(item.ref),
  );
}

/// [layout] without the item [id] and whatever is in it. Cards that are then
/// on no panel are noted as removed, so the TV does not put them back as if
/// they were new apps.
Layout removeItem(Layout layout, String id) {
  final gone = <LayoutItem>[];
  final rest = _rebuilt(
    layout,
    (_, items) => [
      for (final item in items)
        if (item.id == id) ...[] else item,
    ],
  );
  for (final panel in layout.panels) {
    for (final pane in panel.root.panes) {
      for (final item in pane.items) {
        if (item.id != id) continue;
        gone.addAll(switch (item.pane) {
          null => [item],
          final inner => inner.contents,
        });
      }
    }
  }
  final placed = {
    for (final panel in rest.panels)
      for (final item in panel.items)
        if (item.kind == ItemKind.card) item.ref,
  };
  return Layout(
    inbox: rest.inbox,
    panels: rest.panels,
    removed: {
      ...rest.removed,
      for (final item in gone)
        if (item.kind == ItemKind.card && !placed.contains(item.ref)) item.ref,
    },
  );
}

/// How many times each card is somewhere in [layout], by card id.
Map<String, int> placedCounts(Layout layout) {
  final counts = <String, int>{};
  for (final panel in layout.panels) {
    for (final item in panel.items) {
      if (item.kind == ItemKind.card) {
        counts[item.ref] = (counts[item.ref] ?? 0) + 1;
      }
    }
  }
  return counts;
}
