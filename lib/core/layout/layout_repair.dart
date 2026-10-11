import 'package:openlauncher/core/actions/defaults.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/panel.dart';
import 'package:openlauncher/core/layout/rules.dart';

/// [rules] with those in [sound] as they are there, a number written
/// without a fraction where it has none; one that is null is left out.
Map<String, Object?> _kept(
  Map<String, Object?> rules,
  Map<String, Object?> sound,
) => {
  for (final MapEntry(:key, :value) in {...rules, ...sound}.entries)
    if (value != null) key: value is double ? tidy(value) : value,
};

/// Making a layout fit to use: what was read made sound, and the entities there
/// are matched to it.
extension LayoutRepair on Layout {
  /// A copy with everything the rest of the app relies on made true: a home
  /// panel, unique ids, sizes and positions that fit their pane, panes
  /// nested no deeper than [Component.maxDepth], links
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

    // One set of ids for everything: a pane is a component like the rest.
    final ids = <String>{};
    String fresh(String wanted, String fallback) {
      final id = freeId(wanted.isEmpty ? fallback : wanted, ids);
      ids.add(id);
      return id;
    }

    late Component Function(Component, PanelKind, int) repair;

    /// [item] made to fit [parent]; several when it is a pane that cannot
    /// stay one, and none when it is nothing.
    Iterable<Component> fitted(
      Component item,
      Component parent,
      PanelKind kind,
      int depth,
    ) sync* {
      if (item.isPane) {
        // Too deep: what is in it moves up a level.
        if (depth >= Component.maxDepth) {
          for (final child in item.children) {
            yield* fitted(child, parent, kind, depth);
          }
          return;
        }
      } else if (item.kind.isEmpty && !item.isInstance ||
          // What opened a folder that is gone has nothing left to open.
          item.prefab == folderPrefabId &&
              !item.handed.any(panelIds.contains)) {
        return;
      }
      final repaired = item.isPane ? repair(item, kind, depth + 1) : item;
      // In a line its transform is not in cells.
      if (parent.mode.inLine) {
        yield repaired.isPane
            ? repaired
            : repaired.copyWith(id: fresh(item.id, 'item'));
        return;
      }
      final columns = parent.columns;
      // Only a free pane keeps fractions of a cell.
      final free = parent.mode == PaneMode.free;
      double fit(double value, num low, num high) =>
          ((free ? value : value.roundToDouble()).clamp(low, high)).toDouble();
      final smallest = free ? Component.minFreeSpan : 1;
      final w = fit(item.w.isFinite ? item.w : 1, smallest, columns);
      final x = item.x, y = item.y;
      // A position is only kept whole; half of one means nothing.
      final placed = x != null && y != null && x.isFinite && y.isFinite;
      yield repaired
          .sized(
            w,
            fit(item.h.isFinite ? item.h : 1, smallest, Component.maxRows),
            x: placed ? fit(x, 0, columns - w) : null,
            y: placed ? fit(y, 0, 999) : null,
          )
          .copyWith(id: repaired.isPane ? null : fresh(item.id, 'item'));
    }

    repair = (pane, kind, depth) {
      final columns = pane.columns.clamp(1, Component.maxColumns);
      // The pane's own id first, so that nothing inside can take it.
      final id = fresh(pane.id, 'pane');
      // A measure that means something, kept within what is allowed.
      double? within(double? value, num low, num high) =>
          value != null && value.isFinite
          ? value.clamp(low, high).toDouble()
          : null;
      final free = pane.mode == PaneMode.free;
      double? cells(double? value, num most) =>
          switch (within(value, free ? Component.minFreeSpan : 1, most)) {
            final span? when !free => span.roundToDouble(),
            final span => span,
          };
      final sound = pane.copyWith(
        id: id,
        options: _kept(pane.options, {
          'mode': pane.mode.name,
          'columns': columns,
          'spacing': within(pane.spacing, 0, Component.maxSpacing),
          'rowHeight': within(
            pane.rowHeight,
            Component.minRowHeight,
            Component.maxRowHeight,
          ),
          'itemW': cells(pane.itemW, columns),
          'itemH': cells(pane.itemH, Component.maxRows),
        }),
      );
      return sound.copyWith(
        children: [
          for (final child in pane.children)
            ...fitted(child, sound, kind, depth),
        ],
      );
    };

    Object? extent(double? size, num least) => size == Panel.fill
        ? 'fill'
        : size != null && size.isFinite
        ? size.clamp(least, Panel.maxExtent).toDouble()
        : null;
    final result = [
      for (final panel in unique)
        panel.copyWith(
          root: repair(panel.root, panel.kind, 1),
          rules: _kept(panel.rules, {
            'width': extent(panel.width, 40),
            'height': extent(panel.height, 40),
            'closed': extent(panel.closed, 0),
            // A choice that is none of those there are is not one made.
            for (final rule in panelRules(panel.kind))
              if (rule.kind == OptionKind.choice &&
                  !rule.choices.containsKey(panel.rules[rule.key]))
                rule.key: null,
          }),
        ),
    ];
    final home = result.firstWhere((panel) => panel.id == Layout.homeId);
    final placed = {
      for (final panel in result)
        for (final item in panel.items)
          if (item.isInstance) ...item.handed,
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
          if (!item.isInstance || item.handed.every(there.contains)) item,
      ],
    );
    final placed = {...removed};
    final itemIds = <String>{};
    for (final panel in kept.panels) {
      for (final item in panel.root.all) {
        itemIds.add(item.id);
        if (item.isInstance) placed.addAll(item.handed);
      }
    }
    // Named after the entity, by what it is called if that is known.
    String autoId(String entityId) {
      final id = freeId(Component.autoId(entityId, names[entityId]), itemIds);
      itemIds.add(id);
      return id;
    }

    final unplaced = [
      for (final id in entityIds)
        if (placed.add(id)) Component.of(id, id: autoId(id)),
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
