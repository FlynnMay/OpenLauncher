import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/built_in_entities.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/sources/pack_entities.dart';

/// Makes entities at runtime; re-run when what it watches changes.
typedef EntityGenerator = Future<List<Entity>> Function(Ref ref);

/// Everything that makes up the entity list, in the order categories are
/// listed. A new source of entities is one entry here.
final List<EntityGenerator> entityGenerators = [
  // Apps and inputs, from the system pack.
  (ref) => ref.watch(packEntitiesProvider(true).future),
  (ref) async => builtInEntities,
  layoutEntities,
  (ref) => ref.watch(packEntitiesProvider(false).future),
  // The user's own: the only ones that are saved.
  (ref) => ref.watch(configProvider.selectAsync((config) => config.entities)),
];

const _layer = {'layer': '{{self.id}}'};

/// A saved layer's layout, with the layer's id: it adds to and removes from
/// what is on that layer.
Entity layoutEntity(String layer) => Entity(
  id: layer,
  category: 'layout',
  label: layer == Layout.homeId ? 'Home screen' : layer,
  actions: const {
    // `what` is an entity id; `to` a pane on the layer, else the inbox.
    'add': EntityAction(
      run: 'launcher://layout/add',
      bound: _layer,
      args: {'what': [], 'to': []},
      label: 'Add',
      icon: 'material:add_circle',
    ),
    'remove': EntityAction(
      run: 'launcher://layout/remove',
      bound: _layer,
      args: {'what': []},
      label: 'Remove',
      icon: 'material:do_not_disturb_on',
    ),
  },
);

Future<List<Entity>> layoutEntities(Ref ref) async => [
  // Joined, so the list is only made again when the ids change.
  for (final id in (await ref.watch(
    configProvider.selectAsync(
      (config) => config.layout.layers.map((layer) => layer.id).join('\n'),
    ),
  )).split('\n'))
    layoutEntity(id),
];
