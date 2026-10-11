import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/layout_repair.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

/// [layout] with missing entities dropped and unplaced auto-placed ones in
/// the inbox.
Layout layoutWith(Layout layout, List<Entity> entities) => layout.withEntities(
  [
    for (final entity in entities)
      if (entity.placed) entity.id,
  ],
  known: {for (final entity in entities) entity.id},
  names: {for (final entity in entities) entity.id: entity.name},
);

/// [entity] as an instance of its prefab, at that prefab's size, with an id
/// free in [layout].
Component instanceFor(
  Entity entity,
  Layout layout,
  Map<String, Prefab> prefabs,
) {
  final prefab = prefabs[entity.prefab];
  return Component.of(
    entity.id,
    prefab: prefab?.id ?? cardPrefabId,
    w: prefab?.root.w ?? 1,
    h: prefab?.root.h ?? 1,
    id: layout.itemIdFor(Component.autoId(entity.id, entity.name)),
  );
}

Layout resolveLayout(List<Entity> entities, LauncherConfig config) =>
    layoutWith(config.layout, entities);

/// The layout as drawn, kept current with the device and config.
final layoutViewProvider = FutureProvider<Layout>((ref) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  return resolveLayout(entities, config);
});
