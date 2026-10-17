import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layer.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/tree.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// [values] with [sound] merged in; nulls dropped, whole doubles as ints.
Map<String, Object?> _kept(
  Map<String, Object?> values,
  Map<String, Object?> sound,
) => {
  for (final MapEntry(:key, :value) in {...values, ...sound}.entries)
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

    late Node Function(Node, int) repair;

    /// [item] fitted to [parent]: flattened if nested too deep.
    Iterable<Node> fitted(Node item, Node parent, int depth) sync* {
      // Too deep: children move up a level.
      if (item.isPane && !item.isDocked && depth >= Node.maxDepth) {
        for (final child in item.children) {
          yield* fitted(child, parent, depth);
        }
        return;
      }
      // A docked pane starts the count again and takes no cells.
      if (item.isDocked) {
        yield repair(item, 1);
        return;
      }
      final repaired = item.isPane
          ? repair(item, depth + 1)
          : item.copyWith(id: fresh(item.id, 'item'));
      // Only cells have sizes to fit.
      if (parent.mode.inLine || parent.mode == PaneMode.free) {
        yield repaired;
        return;
      }
      final columns = parent.reach;
      double fit(double value, num low, num high) =>
          value.roundToDouble().clamp(low, high).toDouble();
      final w = fit(item.w.isFinite ? item.w : 1, 1, columns);
      final x = item.x, y = item.y;
      // A position needs both x and y.
      final placed = x != null && y != null && x.isFinite && y.isFinite;
      yield repaired.sized(
        w,
        fit(item.h.isFinite ? item.h : 1, 1, SizingModule.maxRows),
        x: placed ? fit(x, 0, columns - w) : null,
        y: placed ? fit(y, 0, 999) : null,
      );
    }

    Object? extent(double? size, num least) => size == DockModule.fill
        ? 'fill'
        : size != null && size.isFinite
        ? size.clamp(least, DockModule.maxExtent).toDouble()
        : null;

    repair = (pane, depth) {
      // Claim the pane's id before its children's.
      var sound = pane.copyWith(
        id: fresh(pane.id, 'pane', docked: pane.isDocked),
      );
      // Clamps a measure; null if invalid.
      double? within(double? value, num low, num high) =>
          value != null && value.isFinite
          ? value.clamp(low, high).toDouble()
          : null;
      if (pane.values(layoutModule.name) case final layout?) {
        final columns = pane.columns.clamp(1, LayoutModule.maxColumns);
        double? cells(double? value, num most) =>
            within(value, 1, most)?.roundToDouble();
        sound = sound.withModule(
          layoutModule.name,
          _kept(layout, {
            'mode': pane.mode.name,
            'columns': columns,
            'spacing': within(pane.spacing, 0, LayoutModule.maxSpacing),
            'rowHeight': within(
              pane.rowHeight,
              LayoutModule.minRowHeight,
              LayoutModule.maxRowHeight,
            ),
            'itemW': cells(pane.itemW, columns),
            'itemH': cells(pane.itemH, SizingModule.maxRows),
          }),
        );
      }
      if (pane.values(dockModule.name) case final dock? when pane.isDocked) {
        sound = sound.withModule(
          dockModule.name,
          _kept(dock, {
            'width': extent(pane.dockWidth, 40),
            'height': extent(pane.dockHeight, 40),
            // Only one on an edge has a closed strip.
            'closed': pane.edge == null ? null : extent(pane.closed, 0),
            // Drop unknown choice values.
            for (final field in dockModule.fields)
              if (field.kind == FieldKind.choice &&
                  field.key != 'position' &&
                  !field.choices.containsKey(dock[field.key]))
                field.key: null,
          }),
        );
      }
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
  /// [entityIds] not in [removed] are appended to the [inbox] as made by
  /// [instance], given ids from [names]; one it makes nothing of is left out.
  Layout withEntities(
    Iterable<String> entityIds, {
    required Node? Function(String entityId, String id) instance,
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
      final id = freeId(Node.autoId(entityId, names[entityId]), itemIds);
      itemIds.add(id);
      return id;
    }

    final unplaced = [
      for (final id in entityIds)
        if (placed.add(id)) ?instance(id, autoId(id)),
    ];
    return kept.rebuild(
      (pane, items) => pane.id == inbox ? [...items, ...unplaced] : items,
    );
  }
}
