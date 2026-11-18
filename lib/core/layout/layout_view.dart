import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher_domain/layout/layout.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// [layout] with missing entities dropped and unplaced auto-placed ones in
/// the inbox, as instances of their prefabs.
Layout layoutWith(
  Layout layout,
  List<Node> nodes,
  Map<String, Prefab> prefabs,
) {
  final byId = {for (final node in nodes) node.id: node};
  return layout.withEntities(
    [
      for (final node in nodes)
        if (node.inbox) node.id,
    ],
    instance: (nodeId, id) => switch (byId[nodeId]) {
      final node? => cardFor(prefabs, node.category)?.instance(nodeId, id: id),
      null => null,
    },
    known: byId.keys.toSet(),
    names: {for (final node in nodes) node.id: node.deviceName},
  );
}

/// The thing called [id] of [category], by its device [name], as an instance
/// of the prefab that is its card, at that prefab's size, with an id free in
/// [layout]; null if no prefab takes its category.
Node? instanceFor(
  String id,
  String category,
  String name,
  Layout layout,
  Map<String, Prefab> prefabs,
) => cardFor(
  prefabs,
  category,
)?.instance(id, id: layout.itemIdFor(Node.autoId(id, name)));

/// [instance] with the nodes holding its slots taking how their slots lay
/// out what is in them. For editing; it is not saved.
Node withSlotLayouts(Node instance, Map<String, Prefab> prefabs) {
  if (!instance.isInstance || instance.children.isEmpty) return instance;
  final parts = {
    for (final part in resolved(instance, prefabs).all) ?part.slotHolder: part,
  };
  const lent = [layoutModule, scrollModule, prefabRulesModule];
  return instance.copyWith(
    children: [
      for (final holder in instance.children)
        switch (parts[holder.id]) {
          final part? => holder.copyWith(
            modules: {
              for (final type in lent) type.name: ?part.values(type.name),
              slotModule.name: ?holder.values(slotModule.name),
            },
          ),
          null => holder,
        },
    ],
  );
}

/// [layout] with every instance's slots laid out as their prefabs say.
Layout withSlotLayoutsIn(Layout layout, Map<String, Prefab> prefabs) =>
    layout.rebuild(
      (_, items) => [for (final item in items) withSlotLayouts(item, prefabs)],
    );

/// The layout as drawn, kept current with the device and config.
final layoutViewProvider = FutureProvider<Layout>((ref) async {
  final prefabs = ref.watch(prefabsProvider);
  final nodes = await ref.watch(nodeShapesProvider.future);
  final config = await ref.watch(configProvider.future);
  return layoutWith(
    withDockedInstances(config.layout, prefabs),
    nodes,
    prefabs,
  );
});
