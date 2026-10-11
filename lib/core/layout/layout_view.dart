import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/layout_repair.dart';

/// [layout] matched to the [entities] there are: an instance handed one
/// that is gone is dropped, and those of a kind that is put on the screen
/// of itself, placed nowhere, are in the inbox.
Layout layoutWith(Layout layout, List<Entity> entities) => layout.withEntities(
  [
    for (final entity in entities)
      if (entityKind(entity.kind)?.placed ?? false) entity.id,
  ],
  known: {for (final entity in entities) entity.id},
  names: {for (final entity in entities) entity.id: entity.name},
);

/// [config]'s layout matched to the [entities] there are: what the TV
/// draws.
Layout resolveLayout(List<Entity> entities, LauncherConfig config) =>
    layoutWith(config.layout, entities);

/// The layout as the TV shows it, kept current with the device and config.
final layoutViewProvider = FutureProvider<Layout>((ref) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  return resolveLayout(entities, config);
});
