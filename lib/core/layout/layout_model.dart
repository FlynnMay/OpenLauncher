import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/screen.dart';
import 'package:openlauncher/core/layout/tree.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// The saved layout: the screens, and the one the launcher opens on.
@immutable
class Layout {
  const Layout({
    required this.screens,
    required this.inbox,
    this.removed = const {},
    this.startup = const Startup(''),
  });

  /// The screen a blank layout has.
  static const homeId = 'home';

  /// Only a home screen, receiving entities in its root; for when no pack
  /// gives a starting layout.
  factory Layout.blank() => Layout(
    inbox: Screen.rootId(homeId),
    screens: [Screen.empty(homeId)],
    startup: const Startup(homeId),
  );

  final List<Screen> screens;

  final Startup startup;

  /// The container that receives unplaced entities, e.g. new apps.
  final String inbox;

  /// Entities the user removed; they are not put back in the [inbox].
  final Set<String> removed;

  /// The screen [startup] names, else the first.
  Screen get start => screen(startup.screen) ?? screens.first;

  Screen? screen(String id) {
    for (final screen in screens) {
      if (screen.id == id) return screen;
    }
    return null;
  }

  /// Every component of every screen.
  Iterable<Node> get all => screens.expand((screen) => screen.root.all);

  /// Everything that is not a container.
  Iterable<Node> get items => all.where((item) => !item.isContainer);

  /// The docked containers of the [start] screen.
  Iterable<Node> get docked =>
      start.root.all.where((container) => container.isDocked);

  /// The nodes that open and close: docked, or with an Overlay.
  Iterable<Node> get opening =>
      all.where((node) => node.isDocked || node.isOverlay);

  Node? container(String id) => all
      .where((container) => !container.isInstance && container.id == id)
      .firstOrNull;

  /// The node of id [id], if any.
  Node? find(String id) => all.where((node) => node.id == id).firstOrNull;

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
      screens: jsonList(json, 'screens', Screen.fromJson),
      inbox: jsonOptional<String>(json, 'inbox') ?? '',
      removed: {
        ...?jsonOptional<List<Object?>>(json, 'removed')?.whereType<String>(),
      },
      startup: Startup.fromJson(json['startup']),
    );
  }

  Map<String, Object?> toJson() => {
    'v': saveVersion,
    'inbox': inbox,
    'removed': removed.toList(),
    'startup': startup.toJson(),
    'screens': [for (final screen in screens) screen.toJson()],
  };

  Layout copyWith({
    List<Screen>? screens,
    String? inbox,
    Set<String>? removed,
    Startup? startup,
  }) => Layout(
    screens: screens ?? this.screens,
    inbox: inbox ?? this.inbox,
    removed: removed ?? this.removed,
    startup: startup ?? this.startup,
  );

  /// Rebuilds every container's children with [change]; only [screen]'s if
  /// given.
  Layout rebuild(
    List<Node> Function(Node container, List<Node> items) change, {
    Set<String>? removed,
    String? screen,
  }) => copyWith(
    removed: removed,
    screens: [
      for (final one in screens)
        screen == null || one.id == screen
            ? one.withRoot(one.root.rebuild(change))
            : one,
    ],
  );

  /// Replaces container [id], a screen's root included, with what [change]
  /// returns.
  Layout withContainer(String id, Node Function(Node container) change) {
    Node mapped(Node container) => container.id == id
        ? change(container)
        : container.copyWith(
            children: [for (final child in container.children) mapped(child)],
          );
    return copyWith(
      screens: [
        for (final screen in screens) screen.withRoot(mapped(screen.root)),
      ],
    );
  }

  /// Removes [entityIds] from [screen], or from every screen, and marks them
  /// [removed].
  Layout without(Set<String> entityIds, {String? screen}) => rebuild(
    (_, items) => [
      for (final item in items)
        if (!item.isInstance || !item.handed.any(entityIds.contains)) item,
    ],
    screen: screen,
    removed: {...removed, ...entityIds},
  );

  /// Adds [item] to container [containerId].
  Layout withAdded(Node item, String containerId) => rebuild(
    (container, items) =>
        container.id == containerId ? [...items, item] : items,
    removed: {...removed}..removeAll(item.handed),
  );
}
