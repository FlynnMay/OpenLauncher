import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/sources/pack_entities.dart';

/// Makes entities at runtime; re-run when what it watches changes.
typedef EntityGenerator = Future<List<Entity>> Function(Ref ref);

/// Everything that makes up the entity list, in the order categories are
/// listed. A new source of entities is one entry here.
final List<EntityGenerator> entityGenerators = [
  // The launcher's own, apps and inputs among them, from the System pack.
  (ref) => ref.watch(packEntitiesProvider(true).future),
  (ref) => ref.watch(packEntitiesProvider(false).future),
  // The user's own: the only ones that are saved.
  (ref) => ref.watch(configProvider.selectAsync((config) => config.entities)),
];
