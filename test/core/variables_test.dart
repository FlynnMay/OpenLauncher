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
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

String _render(String source, Map<String, Object?> values) =>
    Template.parse(source).render((root) => values[root]);

void main() {
  group('templates', () {
    const values = <String, Object?>{
      'media': {'playing': true, 'title': 'Song', 'artist': null},
      'weather': {'temperature': 31.5, 'sky': 'rain'},
    };

    test('compare two values', () {
      expect(_render('{{weather.temperature > 30}}', values), 'true');
      expect(_render('{{weather.temperature <= 30}}', values), 'false');
      expect(_render("{{weather.sky == 'rain'}}", values), 'true');
      expect(_render("{{weather.sky != 'rain'}}", values), 'false');
    });

    test('say one of two things by which way that falls', () {
      expect(
        _render("{{media.playing == true ? 'pause' : 'play'}}", values),
        'pause',
      );
      expect(
        _render("{{weather.temperature > 35 ? 'Hot' : 'Fine: ok'}}", values),
        'Fine: ok',
      );
      // Either side may be another value, and a value alone is asked of.
      expect(
        _render("{{media.artist ? media.artist : media.title}}", values),
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
        when: '{{weather.condition}}',
        cases: [
          VarCase(VarTest.equals, 'Rainy', '/icons/rain.png'),
          VarCase(VarTest.contains, 'cloud', '/icons/cloud.png'),
          VarCase(VarTest.above, 30, '{{hot}}'),
        ],
        otherwise: '/icons/sun.png',
      );
      Object? when(Object? condition) => told(icon, {
        'weather': {'condition': condition},
        'hot': '/icons/hot.png',
      });
      expect(when('Rainy'), '/icons/rain.png');
      expect(when('Partly Cloudy'), '/icons/cloud.png');
      expect(when(31), '/icons/hot.png');
      expect(when('Clear'), '/icons/sun.png');
      expect(Variable.fromJson(icon.toJson()).toJson(), icon.toJson());
    });

    test('is written short where there is nothing more to say', () {
      expect(const Variable('app:a').toJson(), 'app:a');
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
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(LauncherConfig(layout: layout)),
          ),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Layout layout(List<LayoutItem> items) => Layout(
      inbox: 'main',
      panels: [
        Panel(
          id: Layout.homeId,
          root: Pane(id: 'main', items: items),
        ),
      ],
    );

    test('who may read a variable is as it says', () async {
      final item = LayoutItem(
        id: 'box',
        kind: ItemKind.component,
        ref: 'text',
        vars: const {
          'secret': Variable('s', access: VarAccess.private),
          'handed': Variable('h'),
          'open': Variable('o', access: VarAccess.public),
          'app': Variable('app:a', access: VarAccess.public),
        },
      );
      final c = container(layout([item]));
      await c.read(entitiesProvider.future);
      final held = c.listen(componentDataProvider('box'), (_, _) {});
      addTearDown(held.close);
      final scope = scopeOf(c.read, 'box', item.vars, const {'outer': 1});
      expect(scope.own.keys, {'outer', 'secret', 'handed', 'open', 'app'});
      expect(scope.inner.keys, {'outer', 'handed', 'open', 'app'});
      expect(scope.public.keys, {'open', 'app'});
      // One that is the id of an entity stands for it.
      expect((scope.own['app']! as Map)['label'], 'Alpha');
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
      final item = LayoutItem(
        id: 'lamp',
        kind: ItemKind.component,
        ref: 'button',
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
      const flip = Act('set', {
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
        const Act('set', {'var': 'on', 'value': true, 'of': 'lamp'}),
        component: 'elsewhere',
      );
      await pumpEventQueue();
      expect(seen, ['dark', 'lit', 'dark', 'lit']);
    });

    test("the launcher's own prefabs are made the same way", () {
      Prefab prefab(String id) =>
          builtInPrefabs.firstWhere((prefab) => prefab.id == id);
      // What each is drawn from is a variable like any other.
      for (final own in builtInPrefabs) {
        if (own.id != folderPrefabId) {
          expect(own.vars.keys, contains('source'), reason: own.id);
        }
      }
      expect(prefab('weather').vars['icon']!.isConditional, isTrue);
      expect(prefab('now-playing').vars['stateIcon']!.isConditional, isTrue);
      // And each can be saved, changed and read back as it was.
      for (final own in builtInPrefabs) {
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
      final item = LayoutItem.of('media', id: 'np', prefab: 'now-playing');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
                        ?.where((entity) => entity.id == 'media')
                        .firstOrNull) {
                      null => const SizedBox(),
                      final media => EntryTile(entry: EntityEntry(item, media)),
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
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);

      playing.playing = NowPlaying(
        packageName: 'p',
        appLabel: 'Player',
        title: 'Song',
        playing: false,
      );
      playing.notifyNowPlayingChanged();
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    });

    test('a pane and a folder are read by their ids', () async {
      final c = container(
        Layout(
          inbox: 'main',
          panels: [
            Panel(
              id: Layout.homeId,
              root: Pane(
                id: 'main',
                title: 'Apps',
                vars: const {
                  'tint': Variable('red', access: VarAccess.public),
                  'kept': Variable('x'),
                },
                items: [LayoutItem.of('app:a', id: 'a')],
              ),
            ),
            Panel(
              id: 'games',
              title: 'Games',
              root: Pane(
                id: 'games/root',
                items: [LayoutItem.of('app:a', id: 'g')],
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
          .run(const Act('set', {'var': 'open', 'value': true, 'of': 'games'}));
      expect(reads("{{games.open == true ? 'open' : 'shut'}}"), 'open');
    });

    testWidgets('what is in a pane reads the pane, and a folder in place '
        'shows where it is', (tester) async {
      final platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
      ], const []);
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'main',
          panels: [
            Panel(
              id: Layout.homeId,
              root: Pane(
                id: 'main',
                columns: 2,
                rowHeight: 200,
                vars: const {'greeting': Variable('Hello')},
                items: [
                  const LayoutItem(
                    id: 't',
                    kind: ItemKind.component,
                    ref: 'text',
                    options: {'text': '{{greeting}} there'},
                    style: {'fontSize': 14},
                  ),
                  LayoutItem.of('games', id: 'f', prefab: folderPrefabId),
                ],
              ),
            ),
            Panel(
              id: 'games',
              title: 'Games',
              position: PopupPosition.inline,
              root: Pane(
                id: 'games/root',
                columns: 1,
                rowHeight: 60,
                items: [LayoutItem.of('app:a', id: 'g')],
              ),
            ),
          ],
        ).normalised(),
      );
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
            launcherPlatformProvider.overrideWithValue(platform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const HomeScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello there'), findsOneWidget);
      final held = find.byWidgetPredicate(
        (widget) => widget is PaneGrid && widget.view.pane.id == 'games/root',
      );
      // Shut, the folder is its name; what it holds is not laid out.
      expect(find.text('Games'), findsOneWidget);
      expect(held, findsNothing);

      ref.read(runtimeVarsProvider.notifier).set('games', openVar, true);
      await tester.pumpAndSettle();
      // In place: no popup over the screen, and what it holds is there.
      expect(find.byType(Dialog), findsNothing);
      expect(held, findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);

      ref.read(runtimeVarsProvider.notifier).set('games', openVar, false);
      await tester.pumpAndSettle();
      expect(held, findsNothing);
    });
  });
}
