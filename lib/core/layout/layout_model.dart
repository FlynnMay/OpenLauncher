import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layer.dart';
import 'package:openlauncher/core/layout/tree.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// The saved layout: the layers of the screen, the home screen first.
@immutable
class Layout {
  const Layout({
    required this.layers,
    required this.inbox,
    this.removed = const {},
  });

  /// The bottom layer, and the entity that adds to and removes from it.
  static const homeId = 'home';

  /// Only a home layer, receiving entities in its root; for when no pack
  /// gives a starting layout.
  factory Layout.blank() =>
      Layout(inbox: Layer.rootId(homeId), layers: [Layer.empty(homeId)]);

  final List<Layer> layers;

  /// The container that receives unplaced entities, e.g. new apps.
  final String inbox;

  /// Entities the user removed; they are not put back in the [inbox].
  final Set<String> removed;

  Layer get home => layer(homeId)!;

  Layer? layer(String id) {
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// Every component of every layer.
  Iterable<Node> get all => layers.expand((layer) => layer.root.all);

  /// Everything that is not a container.
  Iterable<Node> get items => all.where((item) => !item.isContainer);

  /// The docked containers.
  Iterable<Node> get docked => all.where((container) => container.isDocked);

  Node? container(String id) => all
      .where((container) => container.isContainer && container.id == id)
      .firstOrNull;

  /// The node of id [id] that holds or draws others, if any: what an
  /// instance can be handed as well as an entity.
  Node? node(String id) => all
      .where((node) => node.id == id && (node.isContainer || node.isInstance))
      .firstOrNull;

  /// The `iconOverrides` key for a node's picture.
  static String pictureKey(String nodeId) => 'node:$nodeId';

  /// Throws [FormatException] on malformed JSON. Older versions are migrated
  /// first. The result still needs [normalised].
  factory Layout.fromJson(Map<Object?, Object?> saved) {
    final json = migrateLayout(saved);
    return Layout(
      layers: jsonList(json, 'layers', Layer.fromJson),
      inbox: jsonOptional<String>(json, 'inbox') ?? '',
      removed: {
        ...?jsonOptional<List<Object?>>(json, 'removed')?.whereType<String>(),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'v': saveVersion,
    'inbox': inbox,
    'removed': removed.toList(),
    'layers': [for (final layer in layers) layer.toJson()],
  };

  Layout copyWith({List<Layer>? layers, String? inbox, Set<String>? removed}) =>
      Layout(
        layers: layers ?? this.layers,
        inbox: inbox ?? this.inbox,
        removed: removed ?? this.removed,
      );

  /// Rebuilds every container's children with [change]; only [layer]'s if
  /// given.
  Layout rebuild(
    List<Node> Function(Node container, List<Node> items) change, {
    Set<String>? removed,
    String? layer,
  }) => copyWith(
    removed: removed,
    layers: [
      for (final one in layers)
        layer == null || one.id == layer
            ? one.withRoot(one.root.rebuild(change))
            : one,
    ],
  );

  /// Replaces container [id], a layer's root included, with what [change]
  /// returns.
  Layout withContainer(String id, Node Function(Node container) change) {
    Node mapped(Node container) => container.id == id
        ? change(container)
        : container.copyWith(
            children: [
              for (final child in container.children)
                child.isContainer || child.isInstance ? mapped(child) : child,
            ],
          );
    return copyWith(
      layers: [for (final layer in layers) layer.withRoot(mapped(layer.root))],
    );
  }

  /// Removes [entityIds] from [layer], or from every layer, and marks them
  /// [removed].
  Layout without(Set<String> entityIds, {String? layer}) => rebuild(
    (_, items) => [
      for (final item in items)
        if (!item.isInstance || !item.handed.any(entityIds.contains)) item,
    ],
    layer: layer,
    removed: {...removed, ...entityIds},
  );

  /// Adds [item] to container [containerId].
  Layout withAdded(Node item, String containerId) => rebuild(
    (container, items) =>
        container.id == containerId ? [...items, item] : items,
    removed: {...removed}..removeAll(item.handed),
  );
}
