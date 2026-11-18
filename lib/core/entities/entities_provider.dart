import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity_generators.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/entity_node.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// The registry: every node a pack, a generator or the user makes, with the
/// user's names and pictures applied, sorted by category then name.
final nodesProvider = FutureProvider<List<Node>>((ref) async {
  // Every watch before any wait: none may follow a rebuild.
  final config = ref.watch(configProvider.future);
  final packs = ref.watch(packsProvider.future);
  final generated = Future.wait([
    for (final generate in entityGenerators) generate(ref),
  ]);
  return arrangeNodes(
    _firstWithEachId(await generated),
    await config,
    order: Pack.categoriesOf(await packs).keys,
  );
});

// The registry as entities, for what has not yet moved to nodes. This goes
// with `Entity`, in the last step of the node merge.
final entitiesProvider = FutureProvider<List<Entity>>(
  (ref) async => [
    for (final node in await ref.watch(nodesProvider.future))
      entityOfNode(node),
  ],
);

List<Node> _firstWithEachId(List<List<Node>> generated) {
  final known = <String>{};
  return [
    for (final node in generated.expand((nodes) => nodes))
      if (known.add(node.id)) node,
  ];
}

/// Applies the user's pictures and names, then sorts: by category, those in
/// [order] first, then by name.
List<Node> arrangeNodes(
  List<Node> available,
  LauncherConfig config, {
  Iterable<String> order = const [],
}) {
  final pictured = _withCustomPictures(available, config);
  final nodes = [
    for (final node in pictured.values)
      _withBorrowedPicture(_withName(node, config), pictured, config),
  ];
  _sortByCategoryThenName(nodes, available, order);
  return nodes;
}

Map<String, Node> _withCustomPictures(
  List<Node> available,
  LauncherConfig config,
) => {
  for (final node in available)
    node.id: switch (config.iconOverrides[node.id]) {
      null => node,
      // Custom art is treated as full-frame.
      final path => node.withData({
        Entity.icon: path,
        Entity.shape: Entity.banner,
      }),
    },
};

Node _withName(Node node, LauncherConfig config) =>
    switch (config.names[node.id]) {
      final name? => node.withLabel(name),
      null => node,
    };

/// Borrowing is one level deep, so no chains or loops.
Node _withBorrowedPicture(
  Node node,
  Map<String, Node> pictured,
  LauncherConfig config,
) => switch (pictured[config.iconSources[node.id]]) {
  final source? => node.withData({
    Entity.icon: source.data[Entity.icon],
    Entity.shape: source.data[Entity.shape],
  }),
  null => node,
};

/// Categories in [order], then as they first come.
void _sortByCategoryThenName(
  List<Node> nodes,
  List<Node> available,
  Iterable<String> order,
) {
  final categories = {
    ...order,
    for (final node in available) node.category,
  }.toList();
  nodes.sort((a, b) {
    if (a.category != b.category) {
      return categories
          .indexOf(a.category)
          .compareTo(categories.indexOf(b.category));
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// The entities without their values: what the screen is laid out from. The
/// same list while only values change, so a light's state changing does not
/// lay the whole screen out again.
final entityShapesProvider = AsyncNotifierProvider<EntityShapes, List<Entity>>(
  EntityShapes.new,
);

class EntityShapes extends AsyncNotifier<List<Entity>> {
  @override
  Future<List<Entity>> build() async {
    final shapes = [
      for (final entity in await ref.watch(entitiesProvider.future))
        entity.copyWith(data: const {}),
    ];
    final before = state.value;
    return before != null && listEquals(before, shapes) ? before : shapes;
  }
}
