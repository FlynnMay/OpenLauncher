import 'package:openlauncher/core/actions/defaults.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';

/// Making a layout fit to use: what was read made sound, and the entities there
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
          // What opened a folder that is gone has nothing left to open.
          item.kind == ItemKind.prefab &&
              item.ref == folderPrefabId &&
              !panelIds.contains(item.source)) {
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
        vars: item.vars,
        w: w,
        h: fit(item.h.isFinite ? item.h : 1, smallest, Pane.maxRows),
        x: placed ? fit(x, 0, columns - w) : null,
        y: placed ? fit(y, 0, 999) : null,
        options: item.options,
        style: item.style,
        on: item.on,
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
        rowHeight: within(pane.rowHeight, Pane.minRowHeight, Pane.maxRowHeight),
        itemW: cells(pane.itemW, columns),
        itemH: cells(pane.itemH, Pane.maxRows),
        rules: pane.rules,
        vars: pane.vars,
        on: pane.on,
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
          if (item.kind == ItemKind.prefab) ?item.source,
    };
    return Layout(
      panels: result,
      removed: removed.difference(placed),
      inbox: home.root.panes.any((pane) => pane.id == inbox)
          ? inbox
          : home.root.id,
    );
  }

  /// A copy matched to the entities there are. Items drawn from an entity
  /// that no longer exists are dropped; one is known if it is in [known],
  /// which unless given is [entityIds]. The entities in [entityIds] that
  /// are placed nowhere are added to the end of the [inbox] pane, in the
  /// order given, unless the user [removed] them: these are the ones that
  /// are put on the screen of themselves, as a new app is. Each gets an id
  /// after what the device calls it, in [names] by entity id. The quick
  /// actions are added too, where the layout has none of its own.
  Layout withEntities(
    Iterable<String> entityIds, {
    Map<String, String> names = const {},
    Set<String>? known,
  }) {
    // A folder is something to be drawn from too.
    final there = {...known ?? entityIds, for (final panel in panels) panel.id};
    final kept = rebuild(
      (_, items) => [
        for (final item in items)
          if (item.kind != ItemKind.prefab || there.contains(item.source)) item,
      ],
    );
    final placed = {...removed};
    final itemIds = <String>{};
    for (final panel in kept.panels) {
      for (final pane in panel.root.panes) {
        for (final item in pane.items) {
          itemIds.add(item.id);
          if (item.source case final source?
              when item.kind == ItemKind.prefab) {
            placed.add(source);
          }
        }
      }
    }
    // Named after the entity, by what it is called if that is known.
    String autoId(String entityId) {
      final id = freeId(LayoutItem.autoId(entityId, names[entityId]), itemIds);
      itemIds.add(id);
      return id;
    }

    final unplaced = [
      for (final id in entityIds)
        if (placed.add(id)) LayoutItem.of(id, id: autoId(id)),
    ];
    final filled = kept.rebuild(
      (pane, items) => pane.id == inbox ? [...items, ...unplaced] : items,
    );
    // Like an entity placed nowhere, the quick actions are there before they
    // are saved: as they usually are, until the user arranges them.
    if (filled.panel(Layout.menuId) != null) return filled;
    return Layout(
      panels: [...filled.panels, usualMenuPanel()],
      inbox: filled.inbox,
      removed: filled.removed,
    );
  }
}
