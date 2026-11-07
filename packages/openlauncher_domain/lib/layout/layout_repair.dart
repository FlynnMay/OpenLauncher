import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_enums.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/layout/tree.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// [values] with [sound] merged in; nulls dropped, whole doubles as ints.
Map<String, Object?> _kept(
  Map<String, Object?> values,
  Map<String, Object?> sound,
) => {
  for (final MapEntry(:key, :value) in {...values, ...sound}.entries)
    if (value != null) key: value is double ? tidy(value) : value,
};

extension LayoutRepair on Layout {
  /// Enforces what the app relies on: a screen at least, unique ids, sizes
  /// and positions that fit, bounded nesting, a valid [inbox] and [startup].
  Layout normalised() => _Repair(this).repaired();

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

class _Repair {
  _Repair(this._layout) {
    for (final screen in _screens) {
      _ids.add(screen.id);
    }
  }

  final Layout _layout;

  late final List<Screen> _screens = _uniqueScreens();

  /// Cards name a node that opens by its id, so those keep theirs.
  late final Set<String> _reserved = {
    for (final container in _layout.opening) container.id,
  };

  /// Containers, other nodes and screens share one id space.
  final Set<String> _ids = {};

  List<Screen> _uniqueScreens() {
    final screenIds = <String>{};
    final unique = [
      for (final screen in _layout.screens)
        if (screen.id.isNotEmpty && screenIds.add(screen.id)) screen,
    ];
    return unique.isEmpty ? [Screen.empty(Layout.homeId)] : unique;
  }

  Layout repaired() {
    final result = [
      for (final screen in _screens)
        screen.withRoot(_container(screen.root, 1)),
    ];
    final start =
        result
            .where((screen) => screen.id == _layout.startup.screen)
            .firstOrNull ??
        result.first;
    return Layout(
      screens: result,
      removed: _layout.removed.difference(_handedBy(result)),
      inbox: _holdsContainer(result, _layout.inbox)
          ? _layout.inbox
          : start.root.id,
      startup: Startup(start.id, remember: _layout.startup.remember),
    );
  }

  Set<String> _handedBy(List<Screen> screens) => {
    for (final item in screens.expand((screen) => screen.root.contents))
      if (item.isInstance) ...item.handed,
  };

  bool _holdsContainer(List<Screen> screens, String id) => screens.any(
    (screen) =>
        screen.root.cellContainers.any((container) => container.id == id),
  );

  String _freshId(String wanted, String fallback, {bool docked = false}) {
    final id = docked && _reserved.remove(wanted)
        ? wanted
        : freeId(wanted.isEmpty ? fallback : wanted, {..._ids, ..._reserved});
    _ids.add(id);
    return id;
  }

  Node _container(Node container, int depth) {
    // Claim the container's id before its children's.
    final sound = container.withId(
      _freshId(container.id, 'layout', docked: container.offCells),
    );
    final withDock = _withDockModule(
      _withLayoutModule(sound, container),
      container,
    );
    return withDock.copyWith(
      children: [
        for (final child in container.children)
          ..._fitted(child, withDock, depth),
      ],
    );
  }

  Node _withLayoutModule(Node sound, Node container) {
    final layout = container.values(layoutModule.name);
    if (layout == null) return sound;
    final columns = container.columns.clamp(1, LayoutModule.maxColumns);
    // An instance's values are overrides: what it leaves out is its
    // prefab's, not filled in.
    final partial = container.isInstance;
    return sound.withModule(
      layoutModule.name,
      _kept(layout, {
        if (!partial || layout.containsKey('mode')) 'mode': container.mode.name,
        if (!partial || layout.containsKey('columns')) 'columns': columns,
        'spacing': _within(container.spacing, 0, LayoutModule.maxSpacing),
        'rowHeight': _within(
          container.rowHeight,
          LayoutModule.minRowHeight,
          LayoutModule.maxRowHeight,
        ),
        'itemW': _wholeWithin(container.itemW, columns),
        'itemH': _wholeWithin(container.itemH, SizingModule.maxRows),
      }),
    );
  }

  Node _withDockModule(Node sound, Node container) {
    final dock = container.values(dockModule.name);
    if (dock == null || !container.isDocked) return sound;
    return sound.withModule(
      dockModule.name,
      _kept(dock, {
        'width': _extent(container.dockWidth, 40),
        'height': _extent(container.dockHeight, 40),
        // Only one on an edge has a closed strip.
        'closed': container.edge == null ? null : _extent(container.closed, 0),
        // Drop unknown choice values.
        for (final field in dockModule.fields)
          if (field.kind == FieldKind.choice &&
              field.key != 'position' &&
              !field.choices.containsKey(dock[field.key]))
            field.key: null,
      }),
    );
  }

  /// [item] fitted to [parent]: flattened if nested too deep.
  Iterable<Node> _fitted(Node item, Node parent, int depth) sync* {
    // Too deep: children move up a level.
    if (item.isContainer && !item.offCells && depth >= Node.maxDepth) {
      for (final child in item.children) {
        yield* _fitted(child, parent, depth);
      }
      return;
    }
    // One off the cells starts the count again.
    if (item.offCells) {
      yield _container(item, 1);
      return;
    }
    final repaired = item.isContainer
        ? _container(item, depth + 1)
        : item.withId(_freshId(item.id, 'item'));
    // Only cells have sizes to fit.
    yield parent.mode.inLine || parent.mode == LayoutMode.free
        ? repaired
        : _sizedInCells(repaired, item, parent.reach);
  }

  Node _sizedInCells(Node repaired, Node item, int columns) {
    final w = _fit(item.w.isFinite ? item.w : 1, 1, columns);
    final x = item.x, y = item.y;
    // A position needs both x and y.
    final placed = x != null && y != null && x.isFinite && y.isFinite;
    return repaired.sized(
      w,
      _fit(item.h.isFinite ? item.h : 1, 1, SizingModule.maxRows),
      x: placed ? _fit(x, 0, columns - w) : null,
      y: placed ? _fit(y, 0, 999) : null,
    );
  }

  static double _fit(double value, num low, num high) =>
      value.roundToDouble().clamp(low, high).toDouble();

  /// Clamps a measure; null if invalid.
  static double? _within(double? value, num low, num high) =>
      value != null && value.isFinite
      ? value.clamp(low, high).toDouble()
      : null;

  static double? _wholeWithin(double? value, num most) =>
      _within(value, 1, most)?.roundToDouble();

  static Object? _extent(double? size, num least) => size == DockModule.fill
      ? 'fill'
      : size != null && size.isFinite
      ? size.clamp(least, DockModule.maxExtent).toDouble()
      : null;
}
