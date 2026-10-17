import 'dart:convert';
import 'dart:math';

import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/layout_edit.dart';

/// [node] with [type] added, and the modules it needs. A Layout places the
/// children it takes over.
Node withAdded(Node node, ModuleType type) {
  var next = node;
  for (final need in type.needs) {
    if (moduleNamed(need) case final needed? when !next.added(need)) {
      next = withAdded(next, needed);
    }
  }
  return type == layoutModule
      ? withMode(next, LayoutMode.flow)
      : next.withModule(type.name, type.starter);
}

/// [node] without [type]. Its children keep their places without a Layout;
/// undocked, what only a docked node runs goes too.
Node withRemoved(Node node, ModuleType type) => switch (type) {
  layoutModule => withoutLayout(node),
  dockModule => withDock(node, null),
  _ => node.withModule(type.name, null),
};

/// The modules [node] has that need [type], by label.
List<String> needing(Node node, ModuleType type) => [
  for (final other in moduleTypes)
    if (node.added(other.name) && other.needs.contains(type.name)) other.label,
];

/// [container] without its Layout: each child keeps its cells, or its share
/// of a row or column, as fractions of it.
Node withoutLayout(Node container) {
  final children = container.children;
  final transforms = <NodeTransform?>[];
  if (container.mode.inLine) {
    final count = children.where((child) => !child.isDocked).length;
    var index = 0;
    for (final child in children) {
      if (child.isDocked) {
        transforms.add(null);
        continue;
      }
      final (from, to) = (index / count, (index + 1) / count);
      index++;
      transforms.add(
        container.mode == LayoutMode.row
            ? NodeTransform(minX: from, maxX: to)
            : NodeTransform(minY: from, maxY: to),
      );
    }
  } else {
    final columns = container.reach;
    final placed = placeItems(children, columns, container.mode);
    final rows = placed.fold(1.0, (most, cell) => max(most, cell.y + cell.h));
    for (final (index, child) in children.indexed) {
      final cell = placed[index];
      transforms.add(
        child.isDocked
            ? null
            : NodeTransform(
                minX: cell.x / columns,
                minY: cell.y / rows,
                maxX: (cell.x + cell.w) / columns,
                maxY: (cell.y + cell.h) / rows,
              ),
      );
    }
  }
  return container
      .withModule(layoutModule.name, null)
      .copyWith(
        children: [
          for (final (index, child) in children.indexed)
            switch (transforms[index]) {
              final transform? =>
                child
                    .withModule(sizingModule.name, null)
                    .copyWith(transform: transform),
              null => child,
            },
        ],
      );
}

/// [node] with [type] switched on or off. An instance stores the switch only
/// where it differs from its prefab.
Node withSwitch(
  Node node,
  ModuleType type,
  bool on,
  Map<String, Prefab> prefabs,
) {
  if (!node.isInstance || type.instanceOwned) {
    return node.withValue(type.name, enabledKey, on ? null : false);
  }
  final inherited = !resolved(
    node.withValue(type.name, enabledKey, null),
    prefabs,
  ).isOff(type.name);
  return _tidied(
    node.withValue(type.name, enabledKey, on == inherited ? null : on),
    type,
    prefabs,
  );
}

/// [instance] with [key] of [type] set to [value] over what its prefab
/// gives; the prefab's value takes no override, and null puts back the
/// field's default where the prefab has another.
Node withInstanceValue(
  Node instance,
  ModuleType type,
  String key,
  Object? value,
  Map<String, Prefab> prefabs,
) {
  final own = _tidied(instance.withValue(type.name, key, null), type, prefabs);
  final base = resolved(own, prefabs).modules[type.name] ?? const {};
  if (value == null) {
    if (!base.containsKey(key)) return own;
    final field = type.fields.where((field) => field.key == key).firstOrNull;
    return instance.withValue(type.name, key, field?.defaultValue ?? '');
  }
  return jsonEncode(base[key]) == jsonEncode(value)
      ? own
      : instance.withValue(type.name, key, value);
}

/// [instance] taking [key] of [type] from its prefab again.
Node withInherited(
  Node instance,
  ModuleType type,
  String key,
  Map<String, Prefab> prefabs,
) => _tidied(instance.withValue(type.name, key, null), type, prefabs);

/// [instance] without its own [type] once it sets nothing there that its
/// prefab's does not cover.
Node _tidied(Node instance, ModuleType type, Map<String, Prefab> prefabs) {
  if (instance.modules[type.name]?.isEmpty != true) return instance;
  final bare = instance.withModule(type.name, null);
  return resolved(bare, prefabs).added(type.name) ? bare : instance;
}
