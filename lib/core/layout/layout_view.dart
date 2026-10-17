import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/layout_repair.dart';
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
Component? instanceFor(
  Entity entity,
  Layout layout,
  Map<String, Prefab> prefabs,
) => switch (entity.prefab) {
  final prefab? => prefabs[prefab]?.instance(
    entity.id,
    id: layout.itemIdFor(Component.autoId(entity.id, entity.name)),
  ),
  null => null,
};

/// [item] as the pane it resolves to, if that is docked: an instance of a
/// docked prefab docks like one.
Component? dockedForm(Component item, Map<String, Prefab> prefabs) {
  if (!item.isInstance) return null;
  final pane = resolved(item, prefabs);
  return pane.isDocked ? pane : null;
}

/// [layout] with its instances of docked panes resolved.
Layout withDockedInstances(Layout layout, Map<String, Prefab> prefabs) =>
    layout.rebuild(
      (_, items) => [
        for (final item in items) dockedForm(item, prefabs) ?? item,
      ],
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
