import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/built_in_entities.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/entities/input_artwork.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/sources/pack_entities.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Makes entities at runtime; re-run when what it watches changes.
typedef EntityGenerator = Future<List<Entity>> Function(Ref ref);

/// Everything that makes up the entity list, in the order categories are
/// listed. A new source of entities is one entry here.
final List<EntityGenerator> entityGenerators = [
  (ref) => ref.watch(packEntitiesProvider(true).future),
  inputEntities,
  appEntities,
  (ref) async => builtInEntities,
  layoutEntities,
  (ref) => ref.watch(packEntitiesProvider(false).future),
  // The user's own: the only ones that are saved.
  (ref) => ref.watch(configProvider.selectAsync((config) => config.entities)),
];

const _package = {'package': '{{self.package}}'};

/// What every installed app can be told to do.
const appActions = {
  'open': EntityAction(
    run: 'launchApp',
    bound: _package,
    label: 'Open',
    icon: 'material:play_arrow',
  ),
  'info': EntityAction(
    run: 'openAppInfo',
    bound: _package,
    label: 'App info',
    icon: 'material:info',
  ),
  'uninstall': EntityAction(
    run: 'uninstallApp',
    bound: _package,
    label: 'Uninstall',
    icon: 'material:delete',
  ),
};

Entity appEntity(InstalledApp app) => Entity(
  id: Entity.appId(app.packageName),
  category: appCategory,
  label: app.label,
  prefab: cardPrefabId,
  placed: true,
  data: {
    'package': app.packageName,
    Entity.icon: ?app.iconPath,
    if (app.iconPath != null)
      Entity.shape: app.isBanner ? Entity.banner : 'icon',
  },
  actions: appActions,
);

Future<List<Entity>> appEntities(Ref ref) async => [
  for (final app in await ref.watch(installedAppsProvider.future))
    appEntity(app),
];

const inputActions = {
  'open': EntityAction(
    run: 'switchInput',
    bound: {'input': '{{self.input}}'},
    label: 'Open',
    icon: 'material:play_arrow',
  ),
};

Entity inputEntity(TvInput input) => Entity(
  id: Entity.inputId(input.id),
  category: inputCategory,
  label: input.label,
  prefab: cardPrefabId,
  placed: true,
  data: {
    'input': input.id,
    Entity.icon: inputArtworkSvg(input.kind, input.label),
    Entity.shape: Entity.lineArt,
  },
  actions: inputActions,
);

Future<List<Entity>> inputEntities(Ref ref) async => [
  for (final input in await ref.watch(tvInputsProvider.future))
    inputEntity(input),
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
      run: 'addItem',
      bound: _layer,
      args: {'what': [], 'to': []},
      label: 'Add',
      icon: 'material:add_circle',
    ),
    'remove': EntityAction(
      run: 'removeItem',
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
