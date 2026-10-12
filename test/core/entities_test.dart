import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/tile_actions.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

Entity _entity(String name, {String? icon}) => Entity(
  id: 'app:$name',
  category: appCategory,
  label: name,
  data: {
    'package': name,
    if (icon != null) ...{Entity.icon: icon, Entity.shape: 'icon'},
  },
);

/// Operations that record what they were told.
class _Manager implements OperationsManager {
  _Manager(List<String> names, [List<Object?>? said])
    : operations = [
        for (final name in names)
          Operation(
            name: name,
            label: name,
            args: const {'what': []},
            run: (run) async {
              said?.add(run.args['what']);
              return 'said';
            },
          ),
      ];

  @override
  final List<Operation> operations;
}

void main() {
  group('arrangeEntities', () {
    test('sorts inputs first, then apps, each alphabetically', () {
      const hdmi = Entity(
        id: 'input:x/HW1',
        category: inputCategory,
        label: 'HDMI 1',
      );
      final entities = arrangeEntities([
        _entity('Plex'),
        _entity('alpha'),
        hdmi,
        _entity('Zed'),
      ], LauncherConfig());
      expect(entities.map((c) => c.label), ['HDMI 1', 'alpha', 'Plex', 'Zed']);
    });

    test('icon override replaces the automatic icon', () {
      final entities = arrangeEntities([
        _entity('Plex', icon: '/auto.png'),
      ], LauncherConfig(iconOverrides: {'app:Plex': '/custom.png'}));
      expect(entities.single.data[Entity.icon], '/custom.png');
      expect(entities.single.data[Entity.shape], Entity.banner);
    });

    test('an entity can show the picture of another', () {
      final entities = arrangeEntities(
        [
          _entity('Plex', icon: '/plex.png'),
          _entity('Shim', icon: '/shim.png'),
        ],
        LauncherConfig(
          iconOverrides: {'app:Plex': '/custom.png'},
          // Plex borrowing back is not followed, and a missing entity is
          // ignored.
          iconSources: {'app:Shim': 'app:Plex', 'app:Plex': 'app:Shim'},
        ),
      );
      final shim = entities.firstWhere((c) => c.id == 'app:Shim');
      expect(shim.data[Entity.icon], '/custom.png');
      expect(shim.data[Entity.shape], Entity.banner);
      expect(shim.label, 'Shim');
      expect(
        entities.firstWhere((c) => c.id == 'app:Plex').data[Entity.icon],
        '/shim.png',
      );

      final alone = arrangeEntities([
        _entity('Shim', icon: '/shim.png'),
      ], LauncherConfig(iconSources: {'app:Shim': 'app:Gone'}));
      expect(alone.single.data[Entity.icon], '/shim.png');
    });

    test('a custom name replaces the label and decides the order', () {
      final entities = arrangeEntities([
        _entity('Plex'),
        _entity('alpha'),
      ], LauncherConfig(names: {'app:alpha': 'Zebra'}));
      expect(entities.map((c) => c.label), ['Plex', 'Zebra']);
      expect(entities.last.id, 'app:alpha');
      // What the device calls it is kept, for ids in the layout.
      expect(entities.map((c) => c.name), ['Plex', 'alpha']);
    });
  });

  group('providers', () {
    late MemoryConfigStore store;
    late FakeLauncherPlatform platform;
    late ProviderContainer container;

    setUp(() {
      store = MemoryConfigStore();
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'A', isBanner: false),
        InstalledApp(packageName: 'b', label: 'B', isBanner: false),
      ], []);
      container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(container.dispose);
      // Keep the providers alive for the duration of the test.
      container.listen(layoutViewProvider, (_, _) {});
    });

    /// The apps and inputs on the home screen, in order. The launcher's
    /// own Settings entity is there too, after them.
    Future<List<Entity>> entities() async {
      final all = await container.read(entitiesProvider.future);
      return [
        for (final item in (await container.read(
          layoutViewProvider.future,
        )).home.root.ownContents)
          if (all.byId(item.handed.firstOrNull) case final entity?
              when entity.category != launcherCategory)
            entity,
      ];
    }

    Future<List<String>> ids() async =>
        (await entities()).map((c) => c.id).toList();

    test('config changes are persisted and reflected in entities', () async {
      expect(await ids(), ['app:a', 'app:b']);

      final config = container.read(configProvider.notifier);
      await config.setLayout(Layout.initial(['app:b', 'app:a']));
      expect(await ids(), ['app:b', 'app:a']);
      expect(store.config.layout.items.map((i) => i.handed.firstOrNull), [
        'app:b',
        'app:a',
      ]);

      // Removed entities are gone until they are placed again; they are not
      // mistaken for new apps.
      await config.removeEntity('app:b');
      expect(await ids(), ['app:a']);
      expect(store.config.layout.removed, {'app:b'});
      await config.setLayout(Layout.initial(['app:b', 'app:a']));
      expect(await ids(), ['app:b', 'app:a']);
      expect(store.config.layout.removed, isEmpty);

      await config.setIconOverride('app:a', '/x.png');
      expect(store.config.iconOverrides, {'app:a': '/x.png'});
      await config.setIconOverride('app:a', null);
      expect(store.config.iconOverrides, isEmpty);

      // A custom picture and a borrowed one replace each other.
      await config.setIconOverride('app:a', '/x.png');
      await config.setIconSource('app:a', 'app:b');
      expect(store.config.iconOverrides, isEmpty);
      await config.setIconOverride('app:a', '/x.png');
      expect(store.config.iconSources, isEmpty);
    });

    test('entities refresh when the device reports a package change', () async {
      expect(await ids(), ['app:a', 'app:b']);
      platform.apps = [
        ...platform.apps,
        InstalledApp(packageName: 'c', label: 'C', isBanner: false),
      ];
      platform.notifyAppsChanged();
      await pumpEventQueue();
      expect(await ids(), ['app:a', 'app:b', 'app:c']);
    });

    test('TV inputs become entities, refresh, and switch input', () async {
      platform.inputs = [
        TvInput(id: 'tv/HW15', label: 'HDMI 1', kind: TvInputKind.hdmi),
      ];
      platform.notifyInputsChanged();
      await pumpEventQueue();
      expect(await ids(), ['input:tv/HW15', 'app:a', 'app:b']);

      await container
          .read(actionRunnerProvider)
          .run(const Act('open', {'entity': 'input:tv/HW15'}));
      expect(platform.launched, ['tv/HW15']);
    });

    test('launching an app entity goes to the platform', () async {
      await container
          .read(actionRunnerProvider)
          .run(const Act('open', {'entity': 'app:b'}));
      expect(platform.launched, ['b']);
    });

    test(
      'quick actions follow the saved menu and the kind of entity',
      () async {
        platform.inputs = [
          TvInput(id: 'tv/HW15', label: 'HDMI 1', kind: TvInputKind.hdmi),
        ];
        platform.notifyInputsChanged();
        await pumpEventQueue();
        final actions = container.read(actionRunnerProvider);
        final [input, app, _] = await entities();
        // As when the menu is opened for it: its `source` is set.
        Future<List<String>> offered(Entity entity) async {
          final view = await container.read(layoutViewProvider.future);
          container
              .read(runtimeVarsProvider.notifier)
              .set(Layout.menuId, Component.sourceVar, entity.id);
          return [
            for (final item in offeredFor(
              view.pane(Layout.menuId)!,
              container.read,
              await container.read(entitiesProvider.future),
            ))
              item.options['label'] as String,
          ];
        }

        Future<String?> run(String name, [String? entity]) =>
            actions.run(Act(name, {'entity': ?entity}));

        expect(await offered(app), [
          'Open',
          'App info',
          'Force stop',
          'Uninstall',
          'Remove',
        ]);
        // An input is not an app: nothing to stop or uninstall.
        expect(await offered(input), ['Open', 'Remove']);

        expect(await run('uninstall', app.id), isNull);
        expect(await run('forceStop', app.id), contains('A'));
        expect(platform.appActions, ['uninstall a', 'stop a']);
        // Declined: not an input's to do, no entity named, an entity that
        // is not there, an action nothing has.
        final improper = throwsA(isA<ImproperAct>());
        expect(run('uninstall', input.id), improper);
        expect(run('uninstall'), improper);
        expect(run('uninstall', ''), improper);
        expect(run('uninstall', 'app:gone'), improper);
        expect(run('teleport', app.id), improper);
        // Nor is an owner guessed for an action only one entity has.
        expect(run('setup'), improper);
        expect(run('playPause'), improper);
        expect(actions.run(const Act('remove', {'what': 'app:a'})), improper);
        await pumpEventQueue();
        expect(platform.appActions, hasLength(2));

        // Without ADB the TV's own screen is opened instead.
        platform.canForceStop = false;
        expect(await run('forceStop', app.id), contains('Force stop'));
        expect(platform.appActions.last, 'info a');

        await run('open', app.id);
        expect(platform.launched.last, 'a');

        // Taking it off the screen is the layout's to do, told what.
        // The layout that does it is the home layer's.
        await actions.run(
          const Act('remove', {'entity': 'home', 'what': 'app:a'}),
        );
        expect(await ids(), ['input:tv/HW15', 'app:b']);
        expect(
          actions.run(const Act('remove', {'entity': 'layout', 'what': 'x'})),
          improper,
        );
        // And putting it back: in the inbox, as what its category is drawn
        // as.
        expect(
          await actions.run(
            const Act('add', {'entity': 'home', 'what': 'app:a'}),
          ),
          contains('A'),
        );
        // It is saved where it was put; what is placed nowhere comes after.
        expect(await ids(), ['app:a', 'input:tv/HW15', 'app:b']);
        final layout = container.read(configProvider).value!.layout;
        final added = layout.pane(layout.inbox)!.children.last;
        expect(added.prefab, cardPrefabId);
        expect(added.handed, ['app:a']);
        expect(
          await actions.run(
            const Act('add', {'entity': 'home', 'what': 'app:b', 'to': 'no'}),
          ),
          contains('no'),
        );
      },
    );

    test('a thing does what was set for it, else the usual for its kind', () {
      const entity = Component(
        id: 'a',
        prefab: cardPrefabId,
        vars: {'source': Variable('app:a', type: VarType.entity)},
      );
      // What an instance does is its prefab's to say, unless it says.
      Triggers does(Component item) =>
          resolved(item, {cardPrefabId: builtInPrefabs.first}).on;
      expect(entity.on, isEmpty);
      expect(does(entity), {
        Trigger.press: [
          const Act('open', {'entity': '{{source.id}}'}),
        ],
        Trigger.hold: [
          const Act('set', {
            'entity': 'variables',
            'of': 'quick-actions',
            'var': 'source',
            'value': '{{source.id}}',
          }),
          const Act('set', {
            'entity': 'variables',
            'of': 'quick-actions',
            'var': 'open',
            'value': true,
          }),
        ],
      });
      final quiet = Component.fromJson({
        ...entity.toJson(),
        'on': {
          'hold': <Object?>[],
          'focus': [
            {'do': 'media', 'command': 'pause'},
            {'no': 'name'},
          ],
          'shake': [
            {'do': 'open'},
          ],
        },
      });
      expect(does(quiet), {
        Trigger.press: [
          const Act('open', {'entity': '{{source.id}}'}),
        ],
        Trigger.hold: <Act>[],
        Trigger.focus: [
          const Act('media', {'command': 'pause'}),
        ],
      });
      expect(Component.fromJson(quiet.toJson()).on, quiet.on);
      expect(entity.toJson().containsKey('on'), isFalse);
    });
  });

  group('inputArtworkSvg', () {
    test('badges the port number from the label', () {
      final svg = inputArtworkSvg(TvInputKind.hdmi, 'HDMI 2');
      expect(svg, startsWith('<svg '));
      expect(svg, contains('>2</text>'));
      // Two digits widen the circle into a pill.
      expect(
        inputArtworkSvg(TvInputKind.hdmi, 'HDMI 12'),
        contains('width="36.0"'),
      );
    });

    test('no badge without a number, and a picture per kind', () {
      final pictures = {
        for (final kind in TvInputKind.values) inputArtworkSvg(kind, 'TV'),
      };
      expect(pictures, hasLength(TvInputKind.values.length));
      expect(pictures.any((svg) => svg.contains('<text')), isFalse);
    });
  });

  group('what an entity can do', () {
    ProviderContainer container(List<Entity> own) {
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(LauncherConfig(entities: own)),
          ),
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform(
              [InstalledApp(packageName: 'a', label: 'A', isBanner: true)],
              [TvInput(id: 'x', label: 'X', kind: TvInputKind.hdmi)],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is its own to define, by the names actions go by', () async {
      final c = container(const []);
      final all = await c.read(entitiesProvider.future);
      final app = all.byId('app:a')!, input = all.byId('input:x')!;
      expect(app.actions.keys, ['open', 'info', 'forceStop', 'uninstall']);
      expect(input.actions.keys, ['open']);
      // The same name, done as each defines it.
      expect(app.actions['open']!.run, 'launchApp');
      expect(input.actions['open']!.run, 'switchInput');
      // None belongs to nothing: the rest are the system's, the layers'...
      for (final MapEntry(key: action, value: owner) in const {
        'setup': 'system',
        'newLayer': 'layers',
        'set': 'variables',
        // A layer's layout: there is one for each layer, with its id.
        'add': Layout.homeId,
        'remove': Layout.homeId,
      }.entries) {
        expect(all.byId(owner)!.actions, contains(action), reason: action);
        expect(app.actions, isNot(contains(action)), reason: action);
      }
      // Whatever an entity names to run is there to be run, and nothing is
      // there that no entity runs.
      final operations = c.read(operationsRegistryProvider);
      final run = {
        for (final entity in all)
          for (final action in entity.actions.values) action.run,
      };
      expect(run, {for (final operation in operations.all) operation.name});
    });

    test('two of a category need not do the same', () async {
      const lamp = EntityAction(run: 'setVariable', bound: {'of': 'lamps'});
      final c = container([
        Entity(
          id: 'desk',
          category: 'lamp',
          label: 'Desk',
          actions: {
            'toggle': lamp,
            'dim': EntityAction(
              run: 'setVariable',
              bound: const {'of': 'lamps', 'var': 'desk'},
              args: const {'value': []},
              label: 'Dim',
            ),
          },
        ),
        const Entity(
          id: 'hall',
          category: 'lamp',
          label: 'Hall',
          actions: {'toggle': lamp},
        ),
      ]);
      final all = await c.read(entitiesProvider.future);
      const dim = Act('dim', {'entity': 'desk', 'value': 40, 'var': 'other'});
      expect(isProper(dim, all), isTrue);
      expect(
        isProper(const Act('dim', {'entity': 'hall', 'value': 40}), all),
        isFalse,
      );
      // The editor offers an entity's own actions; every one there is for
      // a target only known as it runs.
      expect(actionsOf('desk', all).keys, ['toggle', 'dim']);
      expect(actionsOf('hall', all).keys, ['toggle']);
      expect(actionsOf(sourceEntity, all).keys, containsAll(['dim', 'open']));
      // Aimed elsewhere, an act keeps only what the new action lets it add.
      expect(
        retargeted(dim, 'hall', 'toggle', actionsOf('hall', all)['toggle']),
        const Act('toggle', {'entity': 'hall'}),
      );
      // An act adds only what the action lets it: `var` stays as bound.
      await c.read(actionRunnerProvider).run(dim);
      expect(c.read(runtimeVarsProvider), {
        'lamps': {'desk': 40},
      });
      expect(
        c
            .read(actionRunnerProvider)
            .run(const Act('dim', {'entity': 'hall', 'value': 40})),
        throwsA(isA<ImproperAct>()),
      );
    });

    test('an action binds what it runs with from its own values', () async {
      final platform = FakeLauncherPlatform(const [], const []);
      final c = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                entities: const [
                  Entity(
                    id: 'plex',
                    category: 'shortcut',
                    label: 'Plex',
                    data: {'package': 'com.plexapp'},
                    actions: {
                      'open': EntityAction(
                        run: 'launchApp',
                        bound: {'package': '{{self.package}}'},
                      ),
                      'lost': EntityAction(run: 'teleport'),
                    },
                  ),
                ],
              ),
            ),
          ),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(c.dispose);
      final actions = c.read(actionRunnerProvider);
      await actions.run(const Act('open', {'entity': 'plex', 'package': 'x'}));
      expect(platform.launched, ['com.plexapp']);
      // What it runs has to be there.
      expect(
        actions.run(const Act('lost', {'entity': 'plex'})),
        throwsA(
          isA<ImproperAct>().having(
            (e) => e.message,
            'message',
            contains('teleport'),
          ),
        ),
      );
    });

    test('an entity is one shape, saved or sent', () {
      const made = Entity(
        id: 'desk',
        category: 'lamp',
        label: 'Desk',
        name: 'Desk lamp',
        data: {'room': 'study'},
        feed: Feed(httpFeed, {'url': 'http://ha/desk', 'every': 30}),
        prefab: cardPrefabId,
        placed: true,
        actions: {
          'dim': EntityAction(
            run: 'setVariable',
            bound: {'var': 'desk'},
            args: {
              'value': ['10', '50'],
            },
            label: 'Dim',
            icon: 'light',
          ),
        },
      );
      expect(Entity.fromJson(made.toJson()), made);
      expect(made.toJson()['actions'], {
        'dim': {
          'run': 'setVariable',
          'with': {'var': 'desk'},
          'args': {
            'value': ['10', '50'],
          },
          'label': 'Dim',
          'icon': 'light',
        },
      });
      // The least there is to say.
      expect(
        Entity.fromJson(const {'id': 'x'}),
        const Entity(id: 'x', category: userCategory, label: 'x'),
      );
      expect(Entity.fromJson(const {'label': 'No id'}), isNull);
    });

    test('operations come from managers, and none twice', () {
      final one = _Manager(['a', 'b']), two = _Manager(['c']);
      expect(
        OperationsRegistry([one, two]).all.map((operation) => operation.name),
        ['a', 'b', 'c'],
      );
      expect(OperationsRegistry([one])['b'], isNotNull);
      expect(OperationsRegistry([one])['c'], isNull);
      expect(
        () => OperationsRegistry([
          one,
          _Manager(['b']),
        ]),
        throwsStateError,
      );
    });

    test('a new group of operations is a manager, and all it takes', () async {
      final said = <Object?>[];
      final platform = FakeLauncherPlatform(const [], const []);
      final c = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                entities: const [
                  Entity(
                    id: 'desk',
                    category: 'lamp',
                    label: 'Desk',
                    data: {'room': 'study', 'on': true, 'brightness': 40},
                    prefab: cardPrefabId,
                    placed: true,
                    actions: {
                      'toggle': EntityAction(
                        run: 'say',
                        bound: {'what': '{{self.label}} in the {{self.room}}'},
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
          launcherPlatformProvider.overrideWithValue(platform),
          operationsManagersProvider.overrideWith(
            (ref) => [
              AppOperationsManager(platform),
              _Manager(['say'], said),
            ],
          ),
        ],
      );
      addTearDown(c.dispose);
      final all = await c.read(entitiesProvider.future);
      // Listed after what the launcher has, and placed like any.
      expect(all.last.id, 'desk');
      final view = await c.read(layoutViewProvider.future);
      expect(
        view.home.root.ownContents.map((entry) => entry.handed.firstOrNull),
        contains('desk'),
      );
      // What it holds is read like anything else's.
      final read = c.listen(templateProvider('{{desk}}'), (_, _) {});
      addTearDown(read.close);
      expect(c.read(entityDataProvider('desk')), {
        'text': 'Desk',
        'id': 'desk',
        'label': 'Desk',
        'category': 'lamp',
        'room': 'study',
        'on': true,
        'brightness': 40,
      });
      expect(
        await c
            .read(actionRunnerProvider)
            .run(const Act('toggle', {'entity': 'desk'})),
        'said',
      );
      expect(said, ['Desk in the study']);
    });
  });

  group('entities that provide data', () {
    late FakeLauncherPlatform platform;
    ProviderContainer container() {
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'A', isBanner: true),
      ], const []);
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(platform),
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 11, 15, 4, 9)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<Map<Object?, Object?>> data(ProviderContainer c, String id) async {
      final held = c.listen(entityDataProvider(id), (_, _) {});
      addTearDown(held.close);
      await c.read(entitiesProvider.future);
      await pumpEventQueue();
      return c.read(entityDataProvider(id))! as Map;
    }

    test('the launcher has its own, which are not put on the screen', () async {
      final c = container();
      final all = await c.read(entitiesProvider.future);
      expect(all.map((entity) => entity.id), [
        'app:a',
        'launcher:settings',
        'clock',
        'weather',
        'location',
        'media',
        'system',
        'updates',
        'layers',
        'variables',
        // The home layer's layout.
        'home',
      ]);
      // Only what is placed of itself lands in the inbox.
      final view = await c.read(layoutViewProvider.future);
      expect(
        view.home.root.ownContents.map((entry) => entry.handed.firstOrNull),
        ['app:a', 'launcher:settings'],
      );
      expect((await data(c, 'clock'))['time'], '15:04');
      expect((await data(c, 'clock'))['weekday'], 'Sunday');
    });

    test(
      'an app says what it is, and leaves how it is shown to others',
      () async {
        final app = await data(container(), 'app:a');
        expect((app['label'], app['category']), ('A', appCategory));
        expect(app['package'], isA<String>());
        // How its picture sits in a frame is the card's to work out.
        expect(app.keys, isNot(contains('fit')));
        expect(app.keys, isNot(contains('pad')));
      },
    );

    test('the media player says what plays and is told what to do', () async {
      final c = container();
      expect((await data(c, 'media'))['playing'], isFalse);
      platform.playing = NowPlaying(
        packageName: 'p',
        appLabel: 'Player',
        title: 'Song',
        playing: true,
      );
      platform.notifyNowPlayingChanged();
      await pumpEventQueue();
      final media = await data(c, 'media');
      expect(
        (media['title'], media['app'], media['text']),
        ('Song', 'Player', 'Song'),
      );
      // Its commands are actions it presents, and no other entity's.
      final all = await c.read(entitiesProvider.future);
      final player = all.firstWhere((entity) => entity.id == 'media');
      final app = all.first;
      final actions = c.read(actionRunnerProvider);
      expect(player.actions, contains('next'));
      expect(app.actions, isNot(contains('next')));
      // There is the one player, and it is named all the same.
      await actions.run(const Act('next', {'entity': 'media'}));
      await actions.run(const Act('playPause', {'entity': 'media'}));
      expect(
        actions.run(Act('playPause', {'entity': app.id})),
        throwsA(isA<ImproperAct>()),
      );
      expect(platform.mediaCommands, [
        MediaCommand.next,
        MediaCommand.playPause,
      ]);
    });
  });
}
