import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';

/// Making a layout fit to use: what was read made sound, and the cards there
/// are matched to it.
extension LayoutRepair on Layout {
  /// A copy with everything the rest of the app relies on made true: a home
  /// panel, unique ids, sizes and positions that fit their pane, panes
  /// nested no deeper than [Pane.maxDepth], links
  /// only to popups that exist, and a valid [inbox].
  Layout normalised() {
    final panelIds = <String>{};
    final unique = [
      for (final panel in panels)
        if (panel.id.isNotEmpty && panelIds.add(panel.id)) panel,
    ];
    if (!panelIds.contains(Layout.homeId)) {
      unique.insert(0, Panel.empty(Layout.homeId));
    }
    final popups = {
      for (final panel in unique)
        if (panel.kind == PanelKind.popup) panel.id,
    };

    final paneIds = <String>{};
    final itemIds = <String>{};
    String fresh(Set<String> used, String wanted, String fallback) {
      final id = freeId(wanted.isEmpty ? fallback : wanted, used);
      used.add(id);
      return id;
    }

    late Pane Function(Pane, PanelKind, int) repair;

    /// The item made to fit a pane [columns] wide; several when it is a pane
    /// that cannot stay one, and none when it points at nothing.
    Iterable<LayoutItem> fitted(
      LayoutItem item,
      int columns,
      PaneMode mode,
      PanelKind kind,
      int depth,
    ) sync* {
      final inner = item.pane;
      if (item.kind == ItemKind.pane) {
        if (inner == null) return;
        // Too deep: what is in it moves up a level.
        if (depth >= Pane.maxDepth) {
          for (final entry in inner.items) {
            yield* fitted(entry, columns, mode, kind, depth);
          }
          return;
        }
      } else if (item.ref.isEmpty ||
          item.kind == ItemKind.panel && !popups.contains(item.ref)) {
        return;
      }
      // Only a free pane keeps fractions of a cell.
      final free = mode == PaneMode.free;
      double fit(double value, num low, num high) =>
          ((free ? value : value.roundToDouble()).clamp(low, high)).toDouble();
      final smallest = free ? Pane.minFreeSpan : 1;
      final w = fit(item.w.isFinite ? item.w : 1, smallest, columns);
      final x = item.x, y = item.y;
      // A position is only kept whole; half of one means nothing.
      final placed = x != null && y != null && x.isFinite && y.isFinite;
      final repaired = inner == null ? null : repair(inner, kind, depth + 1);
      yield LayoutItem(
        id: fresh(itemIds, item.id, 'item'),
        kind: item.kind,
        ref: repaired?.id ?? item.ref,
        w: w,
        h: fit(item.h.isFinite ? item.h : 1, smallest, Pane.maxRows),
        x: placed ? fit(x, 0, columns - w) : null,
        y: placed ? fit(y, 0, 999) : null,
        options: item.options,
        style: item.style,
        hideName: item.hideName,
        look: item.look,
        pane: repaired,
      );
    }

    repair = (pane, kind, depth) {
      final columns = pane.columns.clamp(1, Pane.maxColumns);
      // The pane's own id first, so that nothing inside can take it.
      final id = fresh(paneIds, pane.id, 'pane');
      // A measure that means something, kept within what is allowed.
      double? within(double? value, num low, num high) =>
          value != null && value.isFinite
          ? value.clamp(low, high).toDouble()
          : null;
      final free = pane.mode == PaneMode.free;
      double? cells(double? value, num most) =>
          switch (within(value, free ? Pane.minFreeSpan : 1, most)) {
            final span? when !free => span.roundToDouble(),
            final span => span,
          };
      return Pane(
        id: id,
        title: pane.title,
        mode: pane.mode,
        columns: columns,
        items: [
          for (final entry in pane.items)
            ...fitted(entry, columns, pane.mode, kind, depth),
        ],
        style: pane.style,
        spacing: within(pane.spacing, 0, Pane.maxSpacing),
        padding: within(pane.padding, 0, Pane.maxPadding),
        rowHeight: within(pane.rowHeight, Pane.minRowHeight, Pane.maxRowHeight),
        corners: switch (pane.corners) {
          final corners?
              when corners.length == 4 &&
                  corners.every((corner) => corner.isFinite) =>
            [
              for (final corner in corners)
                corner.clamp(0, Pane.maxCorner).toDouble(),
            ],
          _ => null,
        },
        itemLook: pane.itemLook,
        itemW: cells(pane.itemW, columns),
        itemH: cells(pane.itemH, Pane.maxRows),
        itemNames: pane.itemNames,
      );
    };

    double? extent(double? size) => size == null || size == Panel.fill
        ? size
        : size.isFinite
        ? size.clamp(40, Panel.maxExtent).toDouble()
        : null;
    final result = [
      for (final panel in unique)
        panel.copyWith(
          root: repair(panel.root, panel.kind, 1),
          width: extent(panel.width),
          height: extent(panel.height),
          closed: switch (panel.closed) {
            final closed? when closed.isFinite =>
              closed.clamp(0, Panel.maxExtent).toDouble(),
            _ => null,
          },
        ),
    ];
    final home = result.firstWhere((panel) => panel.id == Layout.homeId);
    final placed = {
      for (final panel in result)
        for (final item in panel.items)
          if (item.kind == ItemKind.card) item.ref,
    };
    return Layout(
      panels: result,
      removed: removed.difference(placed),
      inbox: home.root.panes.any((pane) => pane.id == inbox)
          ? inbox
          : home.root.id,
    );
  }

  /// A copy holding only cards in [cardIds]: items for cards that no longer
  /// exist are dropped, and cards placed nowhere are added to the end of the
  /// [inbox] pane, in the order given, unless the user [removed] them. Each
  /// gets an id after what the device calls it, in [names] by card id.
  Layout withCards(
    Iterable<String> cardIds, {
    Map<String, String> names = const {},
  }) {
    final known = cardIds.toSet();
    final kept = rebuild(
      (_, items) => [
        for (final item in items)
          if (item.kind != ItemKind.card || known.contains(item.ref)) item,
      ],
    );
    final placed = {...removed};
    final itemIds = <String>{};
    for (final panel in kept.panels) {
      for (final pane in panel.root.panes) {
        for (final item in pane.items) {
          itemIds.add(item.id);
          if (item.kind == ItemKind.card) placed.add(item.ref);
        }
      }
    }
    // Named after the card, by what it is called if that is known.
    String autoId(String cardId) {
      final id = freeId(LayoutItem.autoId(cardId, names[cardId]), itemIds);
      itemIds.add(id);
      return id;
    }

    final unplaced = [
      for (final id in cardIds)
        if (placed.add(id))
          LayoutItem(id: autoId(id), kind: ItemKind.card, ref: id),
    ];
    return kept.rebuild(
      (pane, items) => pane.id == inbox ? [...items, ...unplaced] : items,
    );
  }
}
