import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layer.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/rules.dart';

/// [rules] with [sound] merged in; nulls dropped, whole doubles as ints.
Map<String, Object?> _kept(
  Map<String, Object?> rules,
  Map<String, Object?> sound,
) => {
  for (final MapEntry(:key, :value) in {...rules, ...sound}.entries)
    if (value != null) key: value is double ? tidy(value) : value,
};

extension LayoutRepair on Layout {
  /// Enforces what the app relies on: the home layer first, unique ids, sizes
  /// and positions that fit, bounded nesting, no links to missing folders, a
  /// valid [inbox].
  Layout normalised() {
    final layerIds = <String>{};
    final unique = [
      for (final layer in layers)
        if (layer.id.isNotEmpty && layerIds.add(layer.id)) layer,
    ];
    final ordered = [
      unique.where((layer) => layer.id == Layout.homeId).firstOrNull ??
          Layer.empty(Layout.homeId),
      for (final layer in unique)
        if (layer.id != Layout.homeId) layer,
    ];

    // Folder cards name a docked pane by its id, so those keep theirs.
    final docked = {for (final pane in this.docked) pane.id};
    final reserved = {...docked};
    // Panes and other components share one id space.
    final ids = <String>{};
    String fresh(String wanted, String fallback, {bool docked = false}) {
      final id = docked && reserved.remove(wanted)
          ? wanted
          : freeId(wanted.isEmpty ? fallback : wanted, {...ids, ...reserved});
      ids.add(id);
      return id;
    }

    late Component Function(Component, int) repair;

    /// [item] fitted to [parent]: flattened if nested too deep, dropped if
    /// invalid.
    Iterable<Component> fitted(
      Component item,
      Component parent,
      int depth,
    ) sync* {
      if (item.isPane) {
        // Too deep: children move up a level.
        if (!item.isDocked && depth >= Component.maxDepth) {
          for (final child in item.children) {
            yield* fitted(child, parent, depth);
          }
          return;
        }
      } else if (item.kind.isEmpty && !item.isInstance ||
          // A folder card whose folder is gone.
          item.prefab == folderPrefabId && !item.handed.any(docked.contains)) {
        return;
      }
      // A docked pane starts the count again and takes no cells.
      if (item.isDocked) {
        yield repair(item, 1);
        return;
      }
      final repaired = item.isPane ? repair(item, depth + 1) : item;
      // No cells in a row or column.
      if (parent.mode.inLine) {
        yield repaired.isPane
            ? repaired
            : repaired.copyWith(id: fresh(item.id, 'item'));
        return;
      }
      final columns = parent.reach;
      // Fractions only in a free pane.
      final free = parent.mode == PaneMode.free;
      double fit(double value, num low, num high) =>
          ((free ? value : value.roundToDouble()).clamp(low, high)).toDouble();
      final smallest = free ? Component.minFreeSpan : 1;
      final w = fit(item.w.isFinite ? item.w : 1, smallest, columns);
      final x = item.x, y = item.y;
      // A position needs both x and y.
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

    Object? extent(double? size, num least) => size == Component.fill
        ? 'fill'
        : size != null && size.isFinite
        ? size.clamp(least, Component.maxExtent).toDouble()
        : null;

    repair = (pane, depth) {
      final columns = pane.columns.clamp(1, Component.maxColumns);
      // Claim the pane's id before its children's.
      final id = fresh(pane.id, 'pane', docked: pane.isDocked);
      // Clamps a measure; null if invalid.
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
          if (pane.isDocked) ...{
            'width': extent(pane.dockWidth, 40),
            'height': extent(pane.dockHeight, 40),
            // Only one on an edge has a closed strip.
            'closed': pane.edge == null ? null : extent(pane.closed, 0),
            // Drop unknown choice values.
            for (final rule in dockRules(pane))
              if (rule.kind == OptionKind.choice &&
                  rule.key != 'dock' &&
                  !rule.choices.containsKey(pane.options[rule.key]))
                rule.key: null,
          },
        }),
      );
      return sound.copyWith(
        children: [
          for (final child in pane.children) ...fitted(child, sound, depth),
        ],
      );
    };

    final result = [
      for (final layer in ordered) layer.withRoot(repair(layer.root, 1)),
    ];
    final home = result.first;
    final placed = {
      for (final layer in result)
        for (final item in layer.root.contents)
          if (item.isInstance) ...item.handed,
    };
    return Layout(
      layers: result,
      removed: removed.difference(placed),
      inbox: home.root.cellPanes.any((pane) => pane.id == inbox)
          ? inbox
          : home.root.id,
    );
  }

  /// Matches the layout to the entities that exist. Instances of missing
  /// entities are dropped ([known] defaults to [entityIds]). Unplaced
  /// [entityIds] not in [removed] are appended to the [inbox], with ids from
  /// [names].
  Layout withEntities(
    Iterable<String> entityIds, {
    Map<String, String> names = const {},
    Set<String>? known,
  }) {
    // Folders count as known.
    final there = {...known ?? entityIds, for (final pane in docked) pane.id};
    final kept = rebuild(
      (_, items) => [
        for (final item in items)
          if (!item.isInstance || item.handed.every(there.contains)) item,
      ],
    );
    final placed = {...removed};
    final itemIds = <String>{};
    for (final item in kept.all) {
      itemIds.add(item.id);
      if (item.isInstance) placed.addAll(item.handed);
    }
    String autoId(String entityId) {
      final id = freeId(Component.autoId(entityId, names[entityId]), itemIds);
      itemIds.add(id);
      return id;
    }

    final unplaced = [
      for (final id in entityIds)
        if (placed.add(id)) Component.of(id, id: autoId(id)),
    ];
    return kept.rebuild(
      (pane, items) => pane.id == inbox ? [...items, ...unplaced] : items,
    );
  }
}
