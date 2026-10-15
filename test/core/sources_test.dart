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

/// A generator of one entity per app, as a pack would write it, ids
/// starting [prefix].
Map<String, Object> _appsAs(String prefix) => {
  'from': 'apps',
  'where': "{{row.package != 'skip.me'}}",
  'entity': {
    'id': '$prefix:{{row.package}}',
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

final _apps = _appsAs('app');

/// A pack's zip: `pack.json` for [id] and [files], JSON unless text.
Uint8List _pack(String id, Map<String, Object> files) => zipOf({
  'pack.json': jsonEncode({'id': id}),
  for (final MapEntry(key: path, value: content) in files.entries)
    path: content is String ? content : jsonEncode(content),
});

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
      final app = entities.byId('app:a.b')!;
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
      expect(entities.byId('app:c.d')!.data[Entity.shape], 'icon');
      expect(entities.byId('app:e.f')!.data.containsKey(Entity.icon), isFalse);
    });

    test('makes the inputs, numbered, with a picture of each kind', () async {
      final c = container();
      final entities = await c.read(entitiesProvider.future);
      final hdmi = entities.byId('input:hw2')!;
      expect(hdmi.category, inputCategory);
      expect(hdmi.data['input'], 'hw2');
      expect(hdmi.data['number'], '2');
      expect(hdmi.data[Entity.shape], Entity.lineArt);
      expect(
        File(hdmi.data[Entity.icon]! as String).readAsStringSync(),
        File('packs/system/images/input-hdmi.svg').readAsStringSync(),
      );
      final tuner = entities.byId('input:tuner')!;
      expect(tuner.data.containsKey('number'), isFalse);
      expect(tuner.data[Entity.icon], endsWith('input-tuner.svg'));

      await c
          .read(actionRunnerProvider)
          .run(const Act('open', {entityArg: 'input:hw2'}));
      expect(platform.launched, ['hw2']);
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
      expect(apps.onDevice, isTrue);
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

  group('a generator', () {
    final generator = Generator.fromJson(_apps)!;

    test('makes an entity of each row it holds for', () {
      final made = generator.entitiesFrom([
        {'package': 'a.b', 'label': 'AB', 'icon': '/a.png', 'banner': true},
        {'package': 'c.d', 'label': 'CD', 'banner': false},
        {'package': 'skip.me', 'label': 'Skip'},
        {'package': 'a.b', 'label': 'Again'},
      ]);
      expect(made.map((entity) => entity.id), ['app:a.b', 'app:c.d']);
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
      addTearDown(container.dispose);
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
      // Not `app:`, which the launcher still makes itself.
      'generators/apps.json': _appsAs('tv'),
      'generators/inputs.json': {
        'from': 'inputs',
        'entity': {
          'id': 'socket:{{row.id}}',
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
        'root': {'id': 'tile', 'kind': 'pane'},
      },
    });

    test('a built-in pack makes entities from the device', () async {
      final c = container({'sys': system});
      final entities = await c.read(entitiesProvider.future);
      final app = entities.byId('tv:a.b')!;
      expect(app.data, {'package': 'a.b', 'icon': '/a.png', 'shape': 'banner'});
      expect(app.actions['open']!.run, 'os://apps/launch');
      expect(entities.byId('tv:skip.me'), isNull);

      // A pack's picture is given as its file; one it does not have, not
      // at all.
      final input = entities.byId('socket:hw1')!;
      expect(input.data['kind'], 'hdmi');
      expect(File(input.data['icon']! as String).readAsStringSync(), _lamp);
      expect(entities.byId('lamp')!.data.containsKey('icon'), isFalse);

      expect(c.read(prefabsProvider)['tile']?.name, 'Tile');
    });

    test('a watched source is read again when the device says', () async {
      final c = container({'sys': system});
      final held = c.listen(entitiesProvider, (_, _) {});
      addTearDown(held.close);
      expect((await c.read(entitiesProvider.future)).byId('tv:c.d'), isNull);

      platform.apps = [
        ...platform.apps,
        InstalledApp(packageName: 'c.d', label: 'CD', isBanner: false),
      ];
      platform.notifyAppsChanged();
      await pumpEventQueue();
      expect((await c.read(entitiesProvider.future)).byId('tv:c.d'), isNotNull);
    });

    test("another pack's ids start with its own", () async {
      final c = container(const {});
      final store = c.read(packStoreProvider);
      Future<String> why(Map<String, Object> files) async =>
          (await refused(store, _pack('ha', files))).message;

      expect(
        await why({
          'entities/x.json': {'id': 'clock'},
        }),
        contains('must start with "ha:"'),
      );
      expect(
        await why({
          'prefabs/x.json': {
            'id': 'tile',
            'root': {'id': 'tile', 'kind': 'pane'},
          },
        }),
        contains('must start with "ha:"'),
      );
      expect(
        await why({
          'sources/apps.json': {'url': 'os://apps'},
          'generators/x.json': _apps,
        }),
        contains('must start with "ha:"'),
      );
      expect(
        await why({
          'generators/x.json': {
            'from': 'states',
            'entity': {'id': 'ha:{{row.id}}'},
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
            'entities/lounge.json': {'id': 'ha:lounge', 'label': 'Lounge'},
            'prefabs/tile.json': {
              'id': 'ha:tile',
              'root': {'id': 'tile', 'kind': 'pane'},
            },
          }),
        ),
      );
      final entities = await c.read(entitiesProvider.future);
      expect(entities.byId('ha:lounge')?.label, 'Lounge');
      expect(c.read(prefabsProvider).containsKey('ha:tile'), isTrue);
    });
  });
}
