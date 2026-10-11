import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layer.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';

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

  /// The quick-actions pane.
  static const menuId = 'quick-actions';

  static const _firstPane = 'main';

  /// A home screen with one full-height pane holding [order].
  factory Layout.initial([List<String> order = const []]) => Layout(
    inbox: _firstPane,
    layers: [
      Layer(
        id: homeId,
        root: Component.pane(
          id: Layer.rootId(homeId),
          mode: PaneMode.free,
          columns: Component.globalColumns,
          children: [
            Component.pane(
              id: _firstPane,
              x: 0.59,
              y: 1.35,
              w: 10.82,
              h: 7.69,
              children: [
                for (final id in order)
                  Component.of(id, id: Component.autoId(id)),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  final List<Layer> layers;

  /// The pane that receives unplaced entities, e.g. new apps.
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
  Iterable<Component> get all => layers.expand((layer) => layer.root.all);

  /// Everything that is not a pane.
  Iterable<Component> get items => all.where((item) => !item.isPane);

  /// The sidebars and folders.
  Iterable<Component> get docked => all.where((pane) => pane.isDocked);

  Component? pane(String id) =>
      all.where((pane) => pane.isPane && pane.id == id).firstOrNull;

  /// The folder [item] opens, if it is an instance handed one.
  String? folderOf(Component item) => !item.isInstance
      ? null
      : item.handed.where((id) => pane(id)?.isDocked ?? false).firstOrNull;

  /// The `iconOverrides` key for a folder's picture.
  static String iconKey(String paneId) => 'folder:$paneId';

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

  /// Rebuilds every pane's children with [change]; only [layer]'s if given.
  Layout rebuild(
    List<Component> Function(Component pane, List<Component> items) change, {
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

  /// Replaces pane [id], a layer's root included, with what [change] returns.
  Layout withPane(String id, Component Function(Component pane) change) {
    Component mapped(Component pane) => pane.id == id
        ? change(pane)
        : pane.copyWith(
            children: [
              for (final child in pane.children)
                child.isPane ? mapped(child) : child,
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

  /// Adds [item] to pane [paneId].
  Layout withAdded(Component item, String paneId) => rebuild(
    (pane, items) => pane.id == paneId ? [...items, item] : items,
    removed: {...removed}..removeAll(item.handed),
  );
}
