import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  test('layers are made, moved to and taken away', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final layers = c.read(layersProvider.notifier);
    // With none above the home screen there is nowhere to move to.
    layers.moveToTop('left');
    expect(c.read(layersProvider), isEmpty);

    layers.create(dim: 0.3);
    layers.moveToTop('left');
    layers.create(blur: 12);
    layers.moveToTop('games');
    final [low, high] = c.read(layersProvider);
    expect((low.blur, high.blur), (0.0, 12.0));
    expect(low.holds, {'left'});
    expect(high.holds, {'games'});
    expect(layerOf(c.read(layersProvider), 'left'), isNotNull);
    // The one a thing is on goes, wherever it is in the pile.
    layers.close('left');
    expect(c.read(layersProvider).single.holds, {'games'});
    layers.close();
    expect(c.read(layersProvider), isEmpty);
  });

  testWidgets('a sidebar revealed is on a layer of its own, as its pane says', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<WidgetRef> show(Triggers on) async {
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...packOverrides,
            launcherPlatformProvider.overrideWithValue(
              FakeLauncherPlatform([
                InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
                InstalledApp(packageName: 'b', label: 'Beta', isBanner: true),
              ], const []),
            ),
            configStoreProvider.overrideWithValue(
              MemoryConfigStore(
                LauncherConfig(
                  layout: Layout(
                    inbox: 'main',
                    removed: const {'system:settings'},
                    layers: [
                      Layer(
                        id: Layout.homeId,
                        root: Component.pane(
                          id: 'main',
                          // In line with the sidebar's row and clear of it
                          // when it is open, so that going right from it
                          // leads here.
                          mode: PaneMode.grid,
                          children: [
                            cardOf('system:app/a', id: 'a', x: 3, y: 0),
                            // What it does when shown is written on it:
                            // [on] over what a new sidebar comes with.
                            sidebarPane('left', 'left').copyWith(
                              on: {...barTriggers(), ...on},
                              children: [cardOf('system:app/b', id: 'b')],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ).normalised(),
                ),
              ),
            ),
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
      return ref;
    }

    // As it comes: a layer of its own while it is open, and none after.
    var ref = await show(const {});
    expect(ref.read(layersProvider), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(ref.read(runtimeVarsProvider)['left']?[openVar], isTrue);
    expect(ref.read(layersProvider).single.holds, {'left'});
    expect(find.byType(BackdropFilter), findsNothing);
    // Still the one sidebar: its one tile, which says its name twice,
    // as what its picture falls back to and under it.
    expect(find.text('Beta'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(ref.read(layersProvider), isEmpty);
    expect(tester.takeException(), isNull);

    // Told to blur what is under it, the layer does.
    ref = await show(const {
      Trigger.reveal: [
        Act('launcher://layers/new', {'blur': 8, 'dim': 0.2}),
        Act('launcher://layers/raise'),
      ],
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    final layer = ref.read(layersProvider).single;
    expect((layer.blur, layer.dim), (8.0, 0.2));
    expect(layer.holds, {'left'});
    expect(find.byType(BackdropFilter), findsOneWidget);

    // Told to do nothing on being revealed, it stays where it is.
    ref = await show(const {Trigger.reveal: [], Trigger.hide: []});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(ref.read(runtimeVarsProvider)['left']?[openVar], isTrue);
    expect(ref.read(layersProvider), isEmpty);
  });

  testWidgets('a folder hovers on a layer that keeps the focus, and Back '
      'takes it away', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = FakeLauncherPlatform([
      InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
      InstalledApp(packageName: 'b', label: 'Beta', isBanner: true),
    ], const []);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          launcherPlatformProvider.overrideWithValue(platform),
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                layout: Layout(
                  inbox: 'main',
                  removed: const {'system:settings', 'system:app/a'},
                  layers: [
                    Layer(
                      id: Layout.homeId,
                      root: Component.pane(
                        id: 'main',
                        children: [
                          cardOf('games', id: 'f', prefab: folderPrefabId),
                          folderPane('games', title: 'Games').copyWith(
                            children: [cardOf('system:app/b', id: 'b')],
                          ),
                        ],
                      ),
                    ),
                  ],
                ).normalised(),
              ),
            ),
          ),
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
    // What is in the folder, laid out only while it shows.
    final held = find.byWidgetPredicate(
      (widget) => widget is PaneGrid && widget.pane.id == 'games',
    );
    expect(held, findsNothing);

    // Pressed, the folder is revealed: on a layer of its own, which
    // darkens what is under it and has the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final layer = ref.read(layersProvider).single;
    expect((layer.modal, layer.dim), (true, 0.54));
    expect(layer.holds, {'games'});
    expect(held, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Back takes the layer away, and the focus is where it was: the same
    // press opens the folder again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ref.read(layersProvider), isEmpty);
    expect(held, findsNothing);
    expect(ref.read(runtimeVarsProvider)['games']?[openVar], isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(held, findsOneWidget);

    // What is in it is what the focus is on: a press opens it, which
    // closes the folder.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(platform.launched, ['b']);
    expect(held, findsNothing);
    expect(ref.read(layersProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
