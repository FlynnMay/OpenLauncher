import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/layout_repair.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// [layout] with missing entities dropped and unplaced auto-placed ones in
/// the inbox, as instances of their prefabs.
Layout layoutWith(
  Layout layout,
  List<Entity> entities,
  Map<String, Prefab> prefabs,
) {
  final byId = {for (final entity in entities) entity.id: entity};
  return layout.withEntities(
    [
      for (final entity in entities)
        if (entity.placed) entity.id,
    ],
    instance: (entityId, id) => switch (byId[entityId]?.prefab) {
      final prefab? => prefabs[prefab]?.instance(entityId, id: id),
      null => null,
    },
    known: byId.keys.toSet(),
    names: {for (final entity in entities) entity.id: entity.name},
  );
}

/// [entity] as an instance of its prefab, at that prefab's size, with an id
/// free in [layout]; null if it has no prefab that takes it.
Node? instanceFor(Entity entity, Layout layout, Map<String, Prefab> prefabs) =>
    switch (entity.prefab) {
      final prefab? => prefabs[prefab]?.instance(
        entity.id,
        id: layout.itemIdFor(Node.autoId(entity.id, entity.name)),
      ),
      null => null,
    };

/// [item] as the container it resolves to, if that is drawn over the screen:
/// an instance of a docked or Overlay prefab is drawn like one.
Node? dockedForm(Node item, Map<String, Prefab> prefabs) {
  if (!item.isInstance) return null;
  final container = resolved(item, prefabs);
  return container.offCells ? container : null;
}

/// [layout] with its instances of docked and Overlay containers resolved.
Layout withDockedInstances(Layout layout, Map<String, Prefab> prefabs) =>
    layout.rebuild(
      (_, items) => [
        for (final item in items) dockedForm(item, prefabs) ?? item,
      ],
    );

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
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  return layoutWith(
    withDockedInstances(config.layout, prefabs),
    entities,
    prefabs,
  );
});
