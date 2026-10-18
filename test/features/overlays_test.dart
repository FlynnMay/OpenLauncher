import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/modules/drawers.dart';
import 'package:openlauncher/features/modules/lifted.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  test('overlays open on top, move up when opened again, and close', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final overlays = c.read(overlaysProvider.notifier);
    overlays.open(const OpenOverlay('left', dim: 0.3));
    overlays.open(const OpenOverlay('games', blur: 12));
    expect(
      [for (final open in c.read(overlaysProvider)) open.id],
      ['left', 'games'],
    );
    // Opened again it is on top, and there is still one of it.
    overlays.open(const OpenOverlay('left'));
    expect(
      [for (final open in c.read(overlaysProvider)) open.id],
      ['games', 'left'],
    );
    // Asked for, a backdrop is what the next opening uses.
    overlays.ask(const OpenOverlay('menu', modal: true));
    overlays.opened('menu', const OpenOverlay('menu'));
    expect(c.read(overlaysProvider).last.modal, isTrue);
    overlays.opened('menu', const OpenOverlay('menu'));
    expect(c.read(overlaysProvider).last.modal, isFalse);
    // Closing one opened by its variable clears it.
    c.read(runtimeVarsProvider.notifier).set('games', openVar, true);
    overlays.close('games');
    expect(c.read(runtimeVarsProvider)['games']?[openVar], isFalse);
    overlays.close();
    overlays.close();
    expect(c.read(overlaysProvider), isEmpty);
  });

  testWidgets(
    'a sidebar shown is over the screen, with the backdrop its Overlay says',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<WidgetRef> show(Node Function(Node bar) change) async {
        late WidgetRef ref;
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ...packOverrides,
              launcherPlatformProvider.overrideWithValue(
                FakeLauncherPlatform([
                  InstalledApp(
                    packageName: 'a',
                    label: 'Alpha',
                    isBanner: true,
                  ),
                  InstalledApp(packageName: 'b', label: 'Beta', isBanner: true),
                ], const []),
              ),
              configStoreProvider.overrideWithValue(
                MemoryConfigStore(
                  LauncherConfig(
                    layout: Layout(
                      inbox: 'main',
                      removed: const {'system:settings'},
                      screens: [
                        Screen(
                          id: Layout.homeId,
                          root: Node.layout(
                            id: 'main',
                            // In line with the sidebar's row and clear of it
                            // when it is open, so that going right from it
                            // leads here.
                            mode: LayoutMode.grid,
                            children: [
                              cardOf('system:app/a', id: 'a', x: 3, y: 0),
                              change(
                                sidebarOf('left', 'left').holds(
                                  children: [cardOf('system:app/b', id: 'b')],
                                ),
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

      // As it comes: over the screen while it is open, and not after.
      var ref = await show((bar) => bar);
      expect(ref.read(overlaysProvider), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(ref.read(runtimeVarsProvider)['left']?[openVar], isTrue);
      expect(ref.read(overlaysProvider).single.id, 'left');
      expect(find.byType(BackdropFilter), findsNothing);
      // Still the one sidebar: its one tile, which says its name twice,
      // as what its picture falls back to and under it.
      expect(find.text('Beta'), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(ref.read(overlaysProvider), isEmpty);
      expect(tester.takeException(), isNull);

      // Told to blur what is under it, it does.
      ref = await show(
        (bar) => bar.withModule(overlayModule.name, {'blur': 8, 'dim': 20}),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final open = ref.read(overlaysProvider).single;
      expect((open.id, open.blur, open.dim), ('left', 8.0, 0.2));
      expect(find.byType(BackdropFilter), findsOneWidget);

      // With its Overlay off, it opens where it is.
      ref = await show(
        (bar) => bar.withModule(overlayModule.name, {enabledKey: false}),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(ref.read(runtimeVarsProvider)['left']?[openVar], isTrue);
      expect(ref.read(overlaysProvider), isEmpty);
    },
  );

  testWidgets('a folder hovers over the screen, keeps the focus, and Back '
      'closes it', (tester) async {
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
                  screens: [
                    Screen(
                      id: Layout.homeId,
                      root: Node.layout(
                        id: 'main',
                        children: [
                          cardOf('games', id: 'f', prefab: folderPrefabId),
                          folderOf(
                            'games',
                            title: 'Games',
                          ).holds(children: [cardOf('system:app/b', id: 'b')]),
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
      (widget) =>
          widget is ChildrenLayout && widget.container.id == 'games/content',
    );
    expect(held, findsNothing);

    // Pressed, the folder opens over the screen, which it darkens, and it
    // has the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final open = ref.read(overlaysProvider).single;
    expect((open.id, open.modal, open.dim), ('games', true, 0.54));
    expect(held, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Back closes it, and the focus is back on what opened it: the same
    // press opens the folder again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ref.read(overlaysProvider), isEmpty);
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
    expect(ref.read(overlaysProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any node can be opened over the screen, from where it is', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform([
              InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
            ], const []),
          ),
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                layout: Layout(
                  inbox: 'main',
                  removed: const {'system:settings'},
                  screens: [
                    Screen(
                      id: Layout.homeId,
                      root: Node.layout(
                        id: 'main',
                        children: [
                          cardOf('system:app/a', id: 'a', x: 2, y: 1),
                          // Not on the cells, and not there until opened.
                          Node.layout(
                                id: 'menu',
                                children: [cardOf('system:app/a', id: 'a2')],
                              )
                              .copyWith(
                                transform: NodeTransform.at(
                                  const Rect.fromLTWH(100, 100, 400, 300),
                                ),
                              )
                              .withModule(overlayModule.name, {'modal': true}),
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
    Future<void> run(String address, Map<String, Object?> args) async {
      await ref
          .read(operationsRegistryProvider)[address]!
          .run(OperationRun(args));
      await tester.pumpAndSettle();
    }

    final card = find.byWidgetPredicate(
      (widget) => widget is NodeView && widget.component.id == 'a',
    );
    final spot = tester.getRect(card.first);
    expect(find.text('Alpha'), findsWidgets);

    // A card with no Overlay is lifted from its spot, which it keeps.
    await run('launcher://overlay/open', {'of': 'a', 'dim': 50});
    final open = ref.read(overlaysProvider).single;
    expect((open.id, open.dim, open.modal), ('a', 0.5, false));
    expect(find.byType(LiftedSpot), findsOneWidget);
    final lifted = find.descendant(
      of: find.byType(Lifted),
      matching: find.byType(NodeView),
    );
    expect(tester.getRect(lifted.first), spot);
    await run('launcher://overlay/close', {'of': 'a'});
    expect(ref.read(overlaysProvider), isEmpty);
    expect(find.byType(LiftedSpot), findsNothing);

    // One with an Overlay opens where its transform puts it, with its own
    // backdrop, and Back closes it.
    final menu = find.byWidgetPredicate(
      (widget) => widget is NodeView && widget.component.id == 'menu',
    );
    expect(menu, findsNothing);
    await run('launcher://overlay/open', {'of': 'menu'});
    expect(ref.read(overlaysProvider).single.modal, isTrue);
    expect(tester.getRect(menu), const Rect.fromLTWH(100, 100, 400, 300));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ref.read(overlaysProvider), isEmpty);
    expect(menu, findsNothing);

    // One that is not on the screen is not opened.
    await run('launcher://overlay/open', {'of': 'nowhere'});
    expect(ref.read(overlaysProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
