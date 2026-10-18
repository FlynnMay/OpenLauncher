import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/screen.dart';
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
  /// Enforces what the app relies on: the home screen first, unique ids,
  /// sizes and positions that fit, bounded nesting, a valid [inbox].
  Layout normalised() {
    final screenIds = <String>{};
    final unique = [
      for (final screen in screens)
        if (screen.id.isNotEmpty && screenIds.add(screen.id)) screen,
    ];
    final ordered = [
      unique.where((screen) => screen.id == Layout.homeId).firstOrNull ??
          Screen.empty(Layout.homeId),
      for (final screen in unique)
        if (screen.id != Layout.homeId) screen,
    ];

    // Cards name a node that opens by its id, so those keep theirs.
    final docked = {for (final container in opening) container.id};
    final reserved = {...docked};
    // Containers and other nodes share one id space.
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
      if (item.isContainer && !item.offCells && depth >= Node.maxDepth) {
        for (final child in item.children) {
          yield* fitted(child, parent, depth);
        }
        return;
      }
      // One off the cells starts the count again.
      if (item.offCells) {
        yield repair(item, 1);
        return;
      }
      final repaired = item.isContainer
          ? repair(item, depth + 1)
          : item.withId(fresh(item.id, 'item'));
      // Only cells have sizes to fit.
      if (parent.mode.inLine || parent.mode == LayoutMode.free) {
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

    repair = (container, depth) {
      // Claim the container's id before its children's.
      var sound = container.withId(
        fresh(container.id, 'layout', docked: container.offCells),
      );
      // Clamps a measure; null if invalid.
      double? within(double? value, num low, num high) =>
          value != null && value.isFinite
          ? value.clamp(low, high).toDouble()
          : null;
      if (container.values(layoutModule.name) case final layout?) {
        final columns = container.columns.clamp(1, LayoutModule.maxColumns);
        double? cells(double? value, num most) =>
            within(value, 1, most)?.roundToDouble();
        // An instance's values are overrides: what it leaves out is its
        // prefab's, not filled in.
        final partial = container.isInstance;
        sound = sound.withModule(
          layoutModule.name,
          _kept(layout, {
            if (!partial || layout.containsKey('mode'))
              'mode': container.mode.name,
            if (!partial || layout.containsKey('columns')) 'columns': columns,
            'spacing': within(container.spacing, 0, LayoutModule.maxSpacing),
            'rowHeight': within(
              container.rowHeight,
              LayoutModule.minRowHeight,
              LayoutModule.maxRowHeight,
            ),
            'itemW': cells(container.itemW, columns),
            'itemH': cells(container.itemH, SizingModule.maxRows),
          }),
        );
      }
      if (container.values(dockModule.name) case final dock?
          when container.isDocked) {
        sound = sound.withModule(
          dockModule.name,
          _kept(dock, {
            'width': extent(container.dockWidth, 40),
            'height': extent(container.dockHeight, 40),
            // Only one on an edge has a closed strip.
            'closed': container.edge == null
                ? null
                : extent(container.closed, 0),
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
          for (final child in container.children)
            ...fitted(child, sound, depth),
        ],
      );
    };

    final result = [
      for (final screen in ordered) screen.withRoot(repair(screen.root, 1)),
    ];
    final home = result.first;
    final placed = {
      for (final screen in result)
        for (final item in screen.root.contents)
          if (item.isInstance) ...item.handed,
    };
    return Layout(
      screens: result,
      removed: removed.difference(placed),
      inbox: home.root.cellContainers.any((container) => container.id == inbox)
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
    // A node can be handed like an entity.
    final there = {
      ...known ?? entityIds,
      for (final node in all)
        if (node.isContainer || node.isInstance) node.id,
    };
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
      (container, items) =>
          container.id == inbox ? [...items, ...unplaced] : items,
    );
  }
}
