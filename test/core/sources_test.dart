import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/sources/sources.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

const _lamp =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<circle cx="5" cy="5" r="4"/></svg>';

/// A generator of one entity per app, as a pack would write it.
const _apps = {
  'from': 'apps',
  'where': "{{row.package != 'skip.me'}}",
  'entity': {
    'id': 'app/{{row.package}}',
    'category': 'app',
    'label': '{{row.label}}',
    'placed': true,
    'data': {
      'package': '{{row.package}}',
      'icon': '{{row.icon}}',
      'shape': "{{row.banner ? 'banner' : 'icon'}}",
    },
    'actions': {
      'open': {
        'run': 'os://apps/launch',
        'with': {'package': '{{row.package}}', 'from': '{{self.id}}'},
      },
    },
  },
};

/// A pack's zip: `pack.json` for [id], needing [requires], and [files],
/// JSON unless text.
Uint8List _pack(
  String id,
  Map<String, Object> files, {
  List<String> requires = const [],
}) => zipOf({
  'pack.json': jsonEncode({'id': id, 'requires': requires}),
  for (final MapEntry(key: path, value: content) in files.entries)
    path: content is String ? content : jsonEncode(content),
});

Future<PackRefused> _refusedDelete(PackStore store, String id) async {
  try {
    await store.delete(id);
  } on PackRefused catch (refusal) {
    return refusal;
  }
  fail('Not refused');
}

void main() {
  group('a template', () {
    Object? row(String root) => root == 'row' ? {'n': 2, 'a': 'x'} : null;

    test('fills only what reads the roots it is given', () {
      expect(Template.parse('{{row.n}}').fill({'row'}, row), 2);
      expect(
        Template.parse('{{row.a}} and {{self.id | upper}}').fill({'row'}, row),
        'x and {{self.id | upper}}',
      );
      expect(
        Template.parse("{{self.on ? 'a' : 'b'}}").fill({'row'}, row),
        "{{self.on ? 'a' : 'b'}}",
      );
      expect(Template.parse('{{row.none}}').fill({'row'}, row), isNull);
    });

    test('finds a part of a value', () {
      String said(String template) =>
          Template.parse(template).render((_) => 'HDMI 12');
      expect(said(r'{{x | match:(\d+)\s*$}}'), '12');
      expect(said('{{x | match:HD}}'), 'HD');
      expect(said('{{x | match:nothing}}'), '');
      expect(said('{{x | match:(}}'), '');
    });
  });

  group('the System pack', () {
    late FakeLauncherPlatform platform;

    ProviderContainer container() {
      platform = FakeLauncherPlatform(
        [
          InstalledApp(
            packageName: 'a.b',
            label: 'AB',
            iconPath: '/a.png',
            isBanner: true,
          ),
          InstalledApp(
            packageName: 'c.d',
            label: 'CD',
            iconPath: '/c.png',
            isBanner: false,
          ),
          InstalledApp(packageName: 'e.f', label: 'EF', isBanner: false),
        ],
        [
          TvInput(id: 'hw2', label: 'HDMI 2', kind: TvInputKind.hdmi),
          TvInput(id: 'tuner', label: 'TV', kind: TvInputKind.tuner),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('makes the apps, as the launcher always has', () async {
      final entities = await container().read(entitiesProvider.future);
      final app = entities.byId(appId('a.b'))!;
      expect(app.category, appCategory);
      expect(app.label, 'AB');
      expect(app.prefab, cardPrefabId);
      expect(app.placed, isTrue);
      expect(app.data, {
        'package': 'a.b',
        Entity.icon: '/a.png',
        Entity.shape: Entity.banner,
      });
      expect(app.actions.keys, ['open', 'info', 'uninstall']);
      expect(
        app.actions['open'],
        isA<EntityAction>()
            .having((action) => action.run, 'run', 'os://apps/launch')
            .having((action) => action.bound, 'bound', {
              'package': '{{self.package}}',
            }),
      );
      expect(entities.byId(appId('c.d'))!.data[Entity.shape], 'icon');
      expect(
        entities.byId(appId('e.f'))!.data.containsKey(Entity.icon),
        isFalse,
      );
    });

    test('makes the inputs, numbered, with a picture of each kind', () async {
      final c = container();
      final entities = await c.read(entitiesProvider.future);
      final hdmi = entities.byId(inputId('hw2'))!;
      expect(hdmi.category, inputCategory);
      expect(hdmi.data['input'], 'hw2');
      expect(hdmi.data['number'], '2');
      expect(hdmi.data[Entity.shape], Entity.lineArt);
      expect(
        File(hdmi.data[Entity.icon]! as String).readAsStringSync(),
        File('packs/system/images/input-hdmi.svg').readAsStringSync(),
      );
      final tuner = entities.byId(inputId('tuner'))!;
      expect(tuner.data.containsKey('number'), isFalse);
      expect(tuner.data[Entity.icon], endsWith('input-tuner.svg'));

      await c
          .read(actionRunnerProvider)
          .run(Act('open', {entityArg: inputId('hw2')}));
      expect(platform.launched, ['hw2']);
    });

    test('starts the home screen, the quick actions on it', () async {
      final c = container();
      final (:id, layout: start) = await c.read(startingLayoutProvider.future);
      expect(id, 'system:home');
      expect(start.inbox, 'main');
      final menu = start.home.root.children.last;
      expect((menu.id, menu.prefab), ('quick-actions', 'system:quick-actions'));

      // Drawn, the instance is a folder in the middle, holding the prefab's
      // buttons.
      await c.read(packContentsProvider.future);
      final menuNode = withDockedInstances(
        start,
        c.read(prefabsProvider),
      ).container('quick-actions')!;
      expect((menuNode.dock, menuNode.hiddenWhenClosed), ('center', true));
      // Under a heading, a list of buttons.
      final list = menuNode.children.last;
      expect(list.children.map((button) => button.vars['label']?.value), [
        'Open',
        'App info',
        'Uninstall',
        'Remove',
      ]);
      expect(list.children.first.id, 'quick-actions/open');
      expect(menuNode.vars.keys, ['source']);
    });

    test('has a folder, a section and a sidebar that hold what is put in '
        'them', () {
      expect(
        [
          for (final prefab in systemPrefabs)
            if (prefab.slots.isNotEmpty)
              (prefab.id, prefab.card, prefab.slots.join()),
        ],
        [
          ('system:folder', 'system:folder-card', 'content'),
          ('system:section', null, 'content'),
          ('system:sidebar', null, 'content'),
        ],
      );
      final sidebar = systemPrefab(sidebarId);
      // Prefab rules name prefabs, given in full like any other name.
      expect(sidebar.rootAs('side').prefabRules.keys, [
        'system:app-card',
        'system:folder-card',
      ]);
      expect(Prefab.fromJson(sidebar.toJson())!.toJson(), sidebar.toJson());
    });

    test('has a picture for every kind of input', () {
      for (final kind in TvInputKind.values) {
        expect(
          File('packs/system/images/input-${kind.name}.svg').existsSync(),
          isTrue,
          reason: kind.name,
        );
      }
    });
  });

  test('a badge widens for its text, which is never markup', () {
    expect(badgeSvg('2'), contains('width="26.0"'));
    expect(badgeSvg('12'), contains('width="36.0"'));
    expect(badgeSvg('<b>'), contains('&lt;b&gt;</text>'));
  });

  group('a source', () {
    test('is http(s) or os, polled or watched', () {
      final apps = Source.fromJson({'url': 'os://apps', 'watch': true})!;
      expect(apps.answeredHere, isTrue);
      expect(apps.watch, isTrue);
      expect(apps.every, isNull);
      expect(
        Source.fromJson({'url': 'https://x.test/a', 'every': 1})!.every,
        HttpFeed.minEvery,
      );
      for (final not in ['file:///etc', 'os://', 'x.test', 4]) {
        expect(Source.fromJson({'url': not}), isNull);
      }
      expect(Source.fromJson(apps.toJson()), apps);
    });

    test('finds its rows in the answer', () {
      final source = Source(Uri.parse('os://x'), rows: 'result.items');
      expect(
        source.rowsOf({
          'result': {
            'items': [1, 2],
          },
        }),
        [1, 2],
      );
      expect(source.rowsOf({'result': {}}), isEmpty);
      expect(Source(Uri.parse('os://x')).rowsOf({'one': 1}), [
        {'one': 1},
      ]);
    });
  });

  group('a feed', () {
    test('is an address, a source of its pack by name, or one in place', () {
      final address = Feed.fromJson('launcher://clock')!;
      expect(address.isAddress, isTrue);
      expect(address.at('clock'), (
        id: 'launcher://clock',
        source: Source(Uri.parse('launcher://clock'), watch: true),
      ));
      final named = Feed.fromJson('states')!;
      expect((named.isAddress, named.at('lounge')), (false, null));
      final inline = Feed.fromJson({'url': 'https://x.test/a', 'every': 30})!;
      expect(inline.at('lounge')?.id, 'lounge');
      expect(inline.at('lounge')?.source.every, 30);
      // Kept as written, even before it can be read.
      final typing = Feed.fromJson({'url': 'https://'})!;
      expect(typing.source, isNull);
      expect(typing.toJson(), {'url': 'https://'});
      for (final feed in [address, named, inline]) {
        expect(Feed.fromJson(feed.toJson()), feed);
      }
      expect(Feed.fromJson(''), isNull);
      expect(Feed.fromJson(4), isNull);
    });

    test("the launcher's own answer at their addresses", () async {
      final c = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 11, 15, 4)),
        ],
      );
      addTearDown(c.dispose);
      final at = Feed('launcher://clock').at('clock')!;
      final held = c.listen(sourceValueProvider(at), (_, _) {});
      addTearDown(held.close);
      expect(
        await c.read(sourceValueProvider(at).future),
        containsPair('time', '15:04'),
      );
      expect(
        () => c.read(
          sourceValueProvider(Feed('launcher://nothing').at('x')!).future,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('a generator', () {
    final generator = Generator.fromJson(_apps)!;

    test('makes an entity of each row it holds for', () {
      final made = generator.entitiesFrom([
        {'package': 'a.b', 'label': 'AB', 'icon': '/a.png', 'banner': true},
        {'package': 'c.d', 'label': 'CD', 'banner': false},
        {'package': 'skip.me', 'label': 'Skip'},
        {'package': 'a.b', 'label': 'Again'},
      ]);
      expect(made.map((entity) => entity.id), ['app/a.b', 'app/c.d']);
      final ab = made.first;
      expect(ab.label, 'AB');
      expect(ab.placed, isTrue);
      expect(ab.data, {'package': 'a.b', 'icon': '/a.png', 'shape': 'banner'});
      // No icon: none in its data.
      expect(made.last.data.containsKey('icon'), isFalse);
      // What reads the entity is left for when the action runs.
      expect(ab.actions['open']!.bound, {
        'package': 'a.b',
        'from': '{{self.id}}',
      });
    });

    test('makes no more than its limit', () {
      final made = generator.entitiesFrom([
        for (var i = 0; i < Generator.maxEntities + 5; i++) {'package': '$i'},
      ]);
      expect(made, hasLength(Generator.maxEntities));
    });
  });

  group('packs with entities', () {
    late Directory tmp;
    late FakeLauncherPlatform platform;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('openlauncher_sources');
      addTearDown(() => tmp.delete(recursive: true));
      platform = FakeLauncherPlatform(
        [
          InstalledApp(
            packageName: 'a.b',
            label: 'AB',
            iconPath: '/a.png',
            isBanner: true,
          ),
          InstalledApp(packageName: 'skip.me', label: 'Skip', isBanner: false),
        ],
        [TvInput(id: 'hw1', label: 'HDMI 1', kind: TvInputKind.hdmi)],
      );
    });

    ProviderContainer container(Map<String, Uint8List> bundled) {
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(platform),
          packsDirProvider.overrideWith(
            (ref) => Directory('${tmp.path}/packs'),
          ),
          bundledPacksProvider.overrideWithValue(BundledPacks(bundled)),
        ],
      );
      addTearDown(() => closePacks(container));
      return container;
    }

    Future<PackRefused> refused(PackStore store, Uint8List zip) async {
      try {
        await store.install(Stream.value(zip));
      } on PackRefused catch (refusal) {
        return refusal;
      }
      fail('Not refused');
    }

    final system = _pack('sys', {
      'sources/apps.json': {'url': 'os://apps', 'watch': true},
      'sources/inputs.json': {'url': 'os://inputs'},
      'generators/apps.json': _apps,
      'generators/inputs.json': {
        'from': 'inputs',
        'entity': {
          'id': 'socket/{{row.id}}',
          'label': '{{row.label}}',
          'data': {'kind': '{{row.kind}}', 'icon': 'pack:sys/images/lamp.svg'},
        },
      },
      'entities/lamp.json': {
        'id': 'lamp',
        'label': 'Lamp',
        'data': {'icon': 'pack:sys/images/none.svg'},
      },
      'images/lamp.svg': _lamp,
      'prefabs/tile.json': {
        'id': 'tile',
        'name': 'Tile',
        'root': {'id': 'tile'},
      },
    });

    test('a built-in pack makes entities from the device', () async {
      final c = container({'sys': system});
      final entities = await c.read(entitiesProvider.future);
      // Its names given its own id.
      final app = entities.byId('sys:app/a.b')!;
      expect(app.data, {'package': 'a.b', 'icon': '/a.png', 'shape': 'banner'});
      expect(app.actions['open']!.run, 'os://apps/launch');
      expect(entities.byId('sys:app/skip.me'), isNull);

      // A pack's picture is given as its file; one it does not have, not
      // at all.
      final input = entities.byId('sys:socket/hw1')!;
      expect(input.data['kind'], 'hdmi');
      expect(File(input.data['icon']! as String).readAsStringSync(), _lamp);
      expect(entities.byId('sys:lamp')!.data.containsKey('icon'), isFalse);

      expect(c.read(prefabsProvider)['sys:tile']?.name, 'Tile');
    });

    test('a watched source is read again when the device says', () async {
      final c = container({'sys': system});
      final held = c.listen(entitiesProvider, (_, _) {});
      addTearDown(held.close);
      expect(
        (await c.read(entitiesProvider.future)).byId('sys:app/c.d'),
        isNull,
      );

      platform.apps = [
        ...platform.apps,
        InstalledApp(packageName: 'c.d', label: 'CD', isBanner: false),
      ];
      platform.notifyAppsChanged();
      await pumpEventQueue();
      expect(
        (await c.read(entitiesProvider.future)).byId('sys:app/c.d'),
        isNotNull,
      );
    });

    test('an entity is fed by a source of its pack, sharing it', () async {
      final c = container(const {});
      final store = c.read(packStoreProvider);
      expect(
        (await refused(
          store,
          _pack('ha', {
            'entities/x.json': {'id': 'x', 'feed': 'nowhere'},
          }),
        )).message,
        contains('not in sources/'),
      );
      await store.install(
        Stream.value(
          _pack('ha', {
            'sources/time.json': {'url': 'launcher://clock'},
            'entities/lounge.json': {'id': 'lounge', 'feed': 'time'},
          }),
        ),
      );
      final lounge = (await c.read(entitiesProvider.future)).byId('ha:lounge')!;
      expect(lounge.feed?.at(lounge.id)?.id, 'ha:time');
      final held = c.listen(entityDataProvider('ha:lounge'), (_, _) {});
      addTearDown(held.close);
      await pumpEventQueue();
      expect(held.read(), containsPair('time', isA<String>()));
      // Sent and saved as it was written.
      expect(lounge.toJson()['feed'], 'time');
    });

    test('a pack writes short names, given its own id as it loads', () async {
      final c = container(const {});
      final store = c.read(packStoreProvider);
      Future<String> why(Map<String, Object> files) async =>
          (await refused(store, _pack('ha', files))).message;

      // What it defines is its own: no other pack's name in it.
      expect(
        await why({
          'entities/x.json': {'id': 'other:x'},
        }),
        contains('must be a name without ":"'),
      );
      expect(
        await why({
          'sources/states.json': {'url': 'os://apps'},
          'generators/x.json': {
            'from': 'states',
            'entity': {'id': 'other:{{row.id}}'},
          },
        }),
        contains('must be a name without ":"'),
      );
      expect(
        await why({
          'generators/x.json': {
            'from': 'states',
            'entity': {'id': '{{row.id}}'},
          },
        }),
        contains('not in sources/'),
      );
      expect(
        await why({
          'sources/x.json': {'url': 'ftp://x'},
        }),
        contains('"url"'),
      );
      expect(await why({'entities/x.json': '{'}), contains('not JSON'));

      await store.install(
        Stream.value(
          _pack('ha', {
            'entities/lounge.json': {
              'id': 'lounge',
              'label': 'Lounge',
              'prefab': 'tile',
            },
            'prefabs/tile.json': {
              'id': 'tile',
              'root': {
                'id': 'tile',
                'modules': {
                  'variables': {
                    'source': {'value': 'lounge', 'type': 'entity'},
                  },
                  'triggers': {
                    'press': [
                      {'do': 'toggle', 'entity': 'lounge'},
                      {'do': 'open', 'entity': '{{source.id}}'},
                    ],
                  },
                },
                'children': [
                  {
                    'id': 'state',
                    'modules': {
                      'text': {
                        'text':
                            "{{lounge.state == 'on' ? 'On' : source.label}}",
                      },
                    },
                  },
                ],
              },
            },
          }),
        ),
      );
      final lounge = (await c.read(entitiesProvider.future)).byId('ha:lounge')!;
      expect((lounge.label, lounge.prefab), ('Lounge', 'ha:tile'));
      final tile = c.read(prefabsProvider)['ha:tile']!.root;
      expect(tile.vars['source']?.value, 'ha:lounge');
      expect(tile.on[Trigger.press], [
        const Act('toggle', {'entity': 'ha:lounge'}),
        const Act('open', {'entity': '{{source.id}}'}),
      ]);
      // A root is its entity's only where it names one; a variable is not.
      expect(
        tile.children.single.values('text')?['text'],
        "{{ha:lounge.state == 'on' ? 'On' : source.label}}",
      );
    });

    test('a pack names another only if it requires it', () async {
      final c = container({'sys': system});
      final store = c.read(packStoreProvider);
      final card = {
        'prefabs/card.json': {
          'id': 'card',
          'root': {'id': 'card', 'prefab': 'sys:tile'},
        },
      };
      expect(
        (await refused(store, _pack('ha', card))).message,
        contains('does not require'),
      );
      expect(
        (await refused(store, _pack('ha', card, requires: ['base']))).message,
        contains('"base" installed first'),
      );
      await store.install(Stream.value(_pack('ha', card, requires: ['sys'])));
      await c.read(packContentsProvider.future);
      expect(c.read(prefabsProvider)['ha:card']?.root.prefab, 'sys:tile');

      // One that another needs stays.
      await store.install(Stream.value(_pack('base', const {})));
      await store.install(
        Stream.value(_pack('lamps', const {}, requires: ['base'])),
      );
      expect((await _refusedDelete(store, 'base')).message, contains('needs'));
    });
  });
}
