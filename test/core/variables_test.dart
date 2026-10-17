import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/modules/drawers.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

String _render(String source, Map<String, Object?> values) =>
    Template.parse(source).render((root) => values[root]);

void main() {
  group('templates', () {
    const values = <String, Object?>{
      'system:media': {'playing': true, 'title': 'Song', 'artist': null},
      'system:weather': {'temperature': 31.5, 'sky': 'rain'},
    };

    test('compare two values', () {
      expect(_render('{{system:weather.temperature > 30}}', values), 'true');
      expect(_render('{{system:weather.temperature <= 30}}', values), 'false');
      expect(_render("{{system:weather.sky == 'rain'}}", values), 'true');
      expect(_render("{{system:weather.sky != 'rain'}}", values), 'false');
    });

    test('say one of two things by which way that falls', () {
      expect(
        _render("{{system:media.playing == true ? 'pause' : 'play'}}", values),
        'pause',
      );
      expect(
        _render(
          "{{system:weather.temperature > 35 ? 'Hot' : 'Fine: ok'}}",
          values,
        ),
        'Fine: ok',
      );
      // Either side may be another value, and a value alone is asked of.
      expect(
        _render(
          "{{system:media.artist ? system:media.artist : system:media.title}}",
          values,
        ),
        'Song',
      );
      // What only looks like one is left to what it is.
      expect(_render('{{nothing | default:?}}', values), '?');
      expect(Template.parse("{{a.b == c ? d.e : 'x'}}").roots, {'a', 'c', 'd'});
    });
  });

  group('a variable', () {
    Object? told(Variable variable, [Map<String, Object?> values = const {}]) =>
        variable.result(
          (template) =>
              Template.parse(template).evaluate((root) => values[root]),
        );

    test('is a value, or a template that reads others', () {
      expect(told(const Variable(7)), 7);
      expect(told(const Variable('{{n}} cats'), {'n': 3}), '3 cats');
      // One value and nothing else stays what it is.
      expect(told(const Variable('{{n}}'), {'n': 3}), 3);
    });

    test('can be told by what something else is', () {
      const icon = Variable(
        null,
        when: '{{system:weather.condition}}',
        cases: [
          VarCase(VarTest.equals, 'Rainy', '/icons/rain.png'),
          VarCase(VarTest.contains, 'cloud', '/icons/cloud.png'),
          VarCase(VarTest.above, 30, '{{hot}}'),
        ],
        otherwise: '/icons/sun.png',
      );
      Object? when(Object? condition) => told(icon, {
        'system:weather': {'condition': condition},
        'hot': '/icons/hot.png',
      });
      expect(when('Rainy'), '/icons/rain.png');
      expect(when('Partly Cloudy'), '/icons/cloud.png');
      expect(when(31), '/icons/hot.png');
      expect(when('Clear'), '/icons/sun.png');
      expect(Variable.fromJson(icon.toJson()).toJson(), icon.toJson());
    });

    test('is written short where there is nothing more to say', () {
      expect(const Variable('system:app/a').toJson(), 'system:app/a');
      expect(const Variable(3, access: VarAccess.public).toJson(), {
        'value': 3,
        'access': 'public',
      });
      expect(Variable.fromJson('x').value, 'x');
      expect(
        Variable.fromJson({'value': 1, 'access': 'private'}).access,
        VarAccess.private,
      );
    });
  });

  group('in the launcher', () {
    late FakeLauncherPlatform platform;
    ProviderContainer container(Layout layout) {
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
      ], const []);
      final c = ProviderContainer(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(LauncherConfig(layout: layout)),
          ),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Layout layout(List<Node> items) => Layout(
      inbox: 'main',
      layers: [
        Layer(
          id: Layout.homeId,
          root: Node.layout(id: 'main', children: items),
        ),
      ],
    );

    test('who may read a variable is as it says', () async {
      final item = drawn(
        'box',
        textModule.name,
        vars: const {
          'secret': Variable('s', access: VarAccess.private),
          'handed': Variable('h'),
          'open': Variable('o', access: VarAccess.public),
          'app': Variable(
            'system:app/a',
            type: VarType.entity,
            access: VarAccess.public,
          ),
          // Text that happens to be an id is only text.
          'said': Variable('system:app/a'),
        },
      );
      final c = container(layout([item]));
      await c.read(entitiesProvider.future);
      final held = c.listen(componentDataProvider('box'), (_, _) {});
      addTearDown(held.close);
      final scope = scopeOf(c.read, 'box', item.vars, const {'outer': 1});
      expect(scope.own.keys, {
        'outer',
        'secret',
        'handed',
        'open',
        'app',
        'said',
      });
      expect(scope.inner.keys, {'outer', 'handed', 'open', 'app', 'said'});
      expect(scope.public.keys, {'open', 'app'});
      // One that holds an entity stands for it; it is the variable that
      // says so, not what it happens to be set to.
      expect((scope.own['app']! as Map)['label'], 'Alpha');
      expect(scope.own['said'], 'system:app/a');
      expect(item.handed, ['system:app/a']);
      // By its id, anything reads what is public and no more.
      String reads(String template) =>
          valueText(readTemplate(c.read, template, const {}));
      expect(reads('{{box.open}} {{box.app.label}}'), 'o Alpha');
      expect(reads('[{{box.secret}}{{box.handed}}]'), '[]');
    });

    test('one inside reads those around it, the nearest first', () {
      final c = container(layout(const []));
      final outer = scopeOf(c.read, 'p', const {
        'colour': Variable('red'),
        'size': Variable(1),
      }, const {});
      final inner = scopeOf(c.read, 'c', const {
        'colour': Variable('blue'),
        'both': Variable('{{colour}} {{size}}'),
      }, outer.inner);
      expect(inner.own['both'], 'blue 1');
      expect(outer.own['colour'], 'red');
    });

    test('set while the launcher runs, what reads it follows', () async {
      final item = drawn(
        'lamp',
        textModule.name,
        vars: const {'on': Variable(false, access: VarAccess.public)},
      );
      final c = container(layout([item]));
      await c.read(entitiesProvider.future);
      final seen = <String>[];
      final held = c.listen(
        templateProvider("{{lamp.on == true ? 'lit' : 'dark'}}"),
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      addTearDown(held.close);
      const flip = Act('launcher://variables/set', {
        'var': 'on',
        'value': '{{lamp.on == true ? false : true}}',
      });
      final actions = c.read(actionRunnerProvider);
      await actions.run(flip, component: 'lamp');
      await pumpEventQueue();
      await actions.run(flip, component: 'lamp');
      await pumpEventQueue();
      // Set on another by naming it.
      await actions.run(
        const Act('launcher://variables/set', {
          'var': 'on',
          'value': true,
          'of': 'lamp',
        }),
        component: 'elsewhere',
      );
      await pumpEventQueue();
      expect(seen, ['dark', 'lit', 'dark', 'lit']);
    });

    test("the launcher's own prefabs are made the same way", () {
      Prefab prefab(String id) =>
          systemPrefabs.firstWhere((prefab) => prefab.id == id);
      // What each is drawn from is a variable like any other; one with a
      // slot is given nodes, and a button is given words, not an entity.
      for (final own in systemPrefabs) {
        if (own.id != folderPrefabId && own.slots.isEmpty) {
          expect(
            own.vars.keys,
            contains(own.id == 'system:button' ? 'label' : 'source'),
            reason: own.id,
          );
        }
      }
      expect(prefab('system:weather').vars['icon']!.isConditional, isTrue);
      expect(
        prefab('system:now-playing').vars['stateIcon']!.isConditional,
        isTrue,
      );
      // And each can be saved, changed and read back as it was.
      for (final own in systemPrefabs) {
        expect(Prefab.fromJson(own.toJson())!.toJson(), own.toJson());
      }
    });

    testWidgets('a prefab draws what its variables come to', (tester) async {
      final playing = FakeLauncherPlatform(const [], const [])
        ..playing = NowPlaying(
          packageName: 'p',
          appLabel: 'Player',
          title: 'Song',
          artist: 'Band',
          playing: true,
        );
      final item = cardOf(
        'system:media',
        id: 'np',
        prefab: 'system:now-playing',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...packOverrides,
            configStoreProvider.overrideWithValue(MemoryConfigStore()),
            launcherPlatformProvider.overrideWithValue(playing),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 80,
                  child: Consumer(
                    builder: (context, ref, _) => switch (ref
                        .watch(entitiesProvider)
                        .value
                        ?.where((entity) => entity.id == 'system:media')
                        .firstOrNull) {
                      null => const SizedBox(),
                      _ => NodeView(component: item),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Song'), findsOneWidget);
      // Told by a comparison, and by a conditional variable.
      expect(find.text('Band · Player'), findsOneWidget);
      expect(packIcon('material:pause_circle'), findsOneWidget);

      playing.playing = NowPlaying(
        packageName: 'p',
        appLabel: 'Player',
        title: 'Song',
        playing: false,
      );
      playing.notifyNowPlayingChanged();
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget);
      expect(packIcon('material:play_arrow'), findsOneWidget);
    });

    test('a container and a folder are read by their ids', () async {
      final c = container(
        Layout(
          inbox: 'main',
          layers: [
            Layer(
              id: Layout.homeId,
              root: Node.layout(
                id: 'main',
                name: 'Apps',
                vars: const {
                  'tint': Variable('red', access: VarAccess.public),
                  'kept': Variable('x'),
                },
                children: [
                  cardOf('system:app/a', id: 'a'),
                  // Docked: in the container's tree, not among what it counts.
                  folderOf(
                    'games',
                    title: 'Games',
                    children: [cardOf('system:app/a', id: 'g')],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await c.read(entitiesProvider.future);
      final held = [
        for (final id in ['main', 'games'])
          c.listen(componentDataProvider(id), (_, _) {}),
      ];
      addTearDown(() {
        for (final one in held) {
          one.close();
        }
      });
      String reads(String template) =>
          valueText(readTemplate(c.read, template, const {}));
      expect(
        reads('{{main.title}} {{main.count}} {{main.tint}}'),
        'Apps 1 red',
      );
      expect(reads('[{{main.kept}}]'), '[]');
      expect(
        reads('{{games}} {{games.count}} {{games.open}}'),
        'Games 1 false',
      );
      // Opened by its variable, as a press on what opens it does.
      await c
          .read(actionRunnerProvider)
          .run(
            const Act('launcher://variables/set', {
              'var': 'open',
              'value': true,
              'of': 'games',
            }),
          );
      expect(reads("{{games.open == true ? 'open' : 'shut'}}"), 'open');
    });

    testWidgets('what is in a container reads the container', (tester) async {
      final platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
      ], const []);
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'main',
          layers: [
            Layer(
              id: Layout.homeId,
              root: Node.layout(
                id: 'main',
                columns: 2,
                layout: const {'rowHeight': 200},
                vars: const {'greeting': Variable('Hello')},
                children: [
                  drawn(
                    't',
                    textModule.name,
                    values: const {'text': '{{greeting}} there'},
                    style: const {'fontSize': 14},
                  ),
                ],
              ),
            ),
          ],
        ).normalised(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...packOverrides,
            configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
            launcherPlatformProvider.overrideWithValue(platform),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello there'), findsOneWidget);
    });
  });
}
