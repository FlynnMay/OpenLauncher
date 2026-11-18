import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/sources/pack_entities.dart';
import 'package:openlauncher_domain/entities/entity_node.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// Makes nodes at runtime; re-run when what it watches changes.
typedef EntityGenerator = Future<List<Node>> Function(Ref ref);

/// Everything that makes up the entity list, in the order categories are
/// listed. A new source of entities is one entry here.
final List<EntityGenerator> entityGenerators = [
  // Every pack's, the launcher's own among them.
  (ref) => ref.watch(packNodesProvider.future),
  // The user's own: the only ones that are saved.
  (ref) async => [
    for (final entity in await ref.watch(
      configProvider.selectAsync((config) => config.entities),
    ))
      nodeOfEntity(entity),
  ],
];
