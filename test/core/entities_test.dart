import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
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
        )).home.root.contents)
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
      expect(store.config.layout.home.items.map((i) => i.handed.firstOrNull), [
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
              view.panel(Layout.menuId)!.root,
              Layout.menuId,
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
        await actions.run(
          const Act('remove', {'entity': 'layout', 'what': 'app:a'}),
        );
        expect(await ids(), ['input:tv/HW15', 'app:b']);
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

  group('kinds of entity', () {
    test('each presents its own actions, by the names actions go by', () {
      const app = Entity(id: 'app:a', category: appCategory, label: 'A');
      const input = Entity(id: 'input:x', category: inputCategory, label: 'X');
      Set<String> presents(Entity entity) => {
        for (final action in actionRegistries)
          if (actionFor(action.name, entity) != null) action.name,
      };
      expect(presents(app), {'open', 'info', 'forceStop', 'uninstall'});
      expect(presents(input), {'open'});
      // The same name, done as each kind does it.
      expect(actionFor('open', app), isNot(same(actionFor('open', input))));
      // None belongs to nothing: the rest are the system's, the layers'...
      for (final MapEntry(key: action, value: owner) in const {
        'setup': 'system',
        'newLayer': 'layers',
        'set': 'variables',
        'remove': 'layout',
      }.entries) {
        final entity = entityRegistry(owner)!.one!;
        expect(actionFor(action, entity), isNotNull, reason: action);
        expect(actionFor(action, app), isNull, reason: action);
      }
      for (final action in actionRegistries) {
        expect(
          entityRegistries.any((kind) => kind.actions.contains(action)),
          isTrue,
          reason: action.name,
        );
      }
    });

    test('a new kind is one entry, and all the launcher needs', () async {
      final lamps = EntityRegistry(
        name: 'lamp',
        label: 'Lamps',
        // Put on the screen of itself, as an app is, and with data of
        // its own beside its name.
        prefab: cardPrefabId,
        placed: true,
        data: (ref, entity) => const {'on': true, 'brightness': 40},
        list: (ref) async => const [
          Entity(id: 'lamp:desk', category: 'lamp', label: 'Desk'),
        ],
        actions: [
          ActionRegistry(
            name: 'toggle',
            label: 'Switch',
            icon: 'light',
            run: (run) async => '${run.entity.label} switched',
          ),
        ],
      );
      entityRegistries.add(lamps);
      addTearDown(() => entityRegistries.remove(lamps));
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform(const [], const []),
          ),
        ],
      );
      addTearDown(container.dispose);
      final all = await container.read(entitiesProvider.future);
      final desk = all.firstWhere((entity) => entity.category == 'lamp');
      // Listed after the kinds that came before it, and placed like any.
      expect(all.last.id, 'lamp:desk');
      final view = await container.read(layoutViewProvider.future);
      expect(
        view.home.root.contents.map((entry) => entry.handed.firstOrNull),
        contains('lamp:desk'),
      );
      // What it provides is read like anything else's.
      final read = container.listen(
        templateProvider('{{lamp:desk}}'),
        (_, _) {},
      );
      addTearDown(read.close);
      expect(container.read(entityDataProvider('lamp:desk')), {
        'text': 'Desk',
        'id': 'lamp:desk',
        'label': 'Desk',
        'category': 'lamp',
        'on': true,
        'brightness': 40,
      });
      // What it presents is offered and done; what apps present is not.
      final actions = container.read(actionRunnerProvider);
      expect(actionRegistries.map((kind) => kind.name), contains('toggle'));
      const toggle = Act('toggle', {'entity': 'lamp:desk'});
      expect(isProper(toggle, all), isTrue);
      expect(
        isProper(const Act('uninstall', {'entity': 'lamp:desk'}), all),
        isFalse,
      );
      expect(await actions.run(toggle), 'Desk switched');
      expect(desk.label, 'Desk');
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
        'layers',
        'variables',
        'layout',
      ]);
      // Only what is placed of itself lands in the inbox.
      final view = await c.read(layoutViewProvider.future);
      expect(view.home.root.contents.map((entry) => entry.handed.firstOrNull), [
        'app:a',
        'launcher:settings',
      ]);
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
      expect(actionFor('next', player), isNotNull);
      expect(actionFor('next', app), isNull);
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
