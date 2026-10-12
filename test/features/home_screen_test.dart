import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/component_view.dart';
import 'package:openlauncher/features/home/docked_pane.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

void main() {
  testWidgets('shows app entities and launches with the D-pad', (tester) async {
    final platform = FakeLauncherPlatform([
      InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
      InstalledApp(packageName: 'pkg.b', label: 'Beta', isBanner: false),
    ], []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(platform),
          configServerProvider.overrideWith((ref) => null),
        ],
        child: const OpenLauncherApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);

    // First entity has focus on start; D-pad centre launches it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(platform.launched, ['pkg.a']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(platform.launched, ['pkg.a', 'pkg.b']);
  });

  group('layout', () {
    late FakeLauncherPlatform platform;

    Future<void> pumpApp(WidgetTester tester, [LauncherConfig? config]) async {
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
        InstalledApp(packageName: 'pkg.b', label: 'Beta', isBanner: false),
        InstalledApp(packageName: 'pkg.c', label: 'Gamma', isBanner: false),
      ], []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
            launcherPlatformProvider.overrideWithValue(platform),
            configServerProvider.overrideWith((ref) => null),
          ],
          child: const OpenLauncherApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// A home layer of [panes] one under another, each five rows tall, with
    /// room on the left for a sidebar, and [docked] on it.
    Layer home(List<Component> panes, [List<Component> docked = const []]) =>
        Layer(
          id: Layout.homeId,
          root: Component.pane(
            id: 'global',
            mode: PaneMode.grid,
            columns: 12,
            children: [
              for (final (index, pane) in panes.indexed)
                pane.sized(10, 5, x: 2, y: index * 5.0),
              ...docked,
            ],
          ),
        );

    /// The docked pane [id] as drawn.
    Finder dock(String id) => find.byWidgetPredicate(
      (widget) => widget is DockedPane && widget.pane.id == id,
    );

    Component entity(String package) => Component(
      id: 'i-$package',
      prefab: cardPrefabId,
      vars: {'source': Variable('app:$package', type: VarType.entity)},
    );

    testWidgets('holding OK offers quick actions instead of opening', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(FocusTile.holdTime);
      await tester.pumpAndSettle();
      expect(find.text('Force stop'), findsOneWidget);

      // The button is still down: holding on and letting go choose nothing.
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Force stop'), findsOneWidget);
      expect(platform.launched, isEmpty);

      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.appActions, ['uninstall pkg.a']);
      expect(find.text('Force stop'), findsNothing);
    });

    testWidgets('the quick actions take off what they were opened for', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Alpha'), findsWidgets);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(FocusTile.holdTime);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // Removing is the layout's to do: the button names what the menu is
      // about, which the menu says in a variable of its own.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Force stop'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsWidgets);
    });

    testWidgets('a menu goes by its entity variable, whatever its name', (
      tester,
    ) async {
      Component button(String label, String action) => Component(
        id: 'pick-$action',
        kind: 'button',
        options: {'label': label},
        on: {
          Trigger.press: [
            Act(action, {'entity': '{{target.id}}'}),
          ],
        },
      );
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [Component.pane(id: 'main')],
                [
                  folderPane('pick').copyWith(
                    vars: const {
                      'target': Variable(null, type: VarType.entity),
                    },
                    children: [
                      button('Start it', 'open'),
                      button('Play it', 'playPause'),
                    ],
                  ),
                ],
              ),
            ],
          ).normalised(),
        ),
      );
      final vars = ProviderScope.containerOf(
        tester.element(find.byType(OpenLauncherApp)),
      ).read(runtimeVarsProvider.notifier);
      Future<void> openFor(String entity) async {
        vars.set('pick', 'target', entity);
        vars.set('pick', openVar, true);
        await tester.pumpAndSettle();
      }

      // Neither can be done to the clock: the menu is not shown.
      await openFor('clock');
      expect(find.text('Start it'), findsNothing);

      // An app has nothing to play.
      await openFor('app:pkg.a');
      expect(find.text('Start it'), findsOneWidget);
      expect(find.text('Play it'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.a']);
      expect(find.text('Start it'), findsNothing);
    });

    testWidgets('a folder opens a popup that closes when an entity is opened', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [
                  Component.pane(
                    id: 'top',
                    title: 'Favourites',
                    mode: PaneMode.grid,
                    columns: 4,
                    children: [
                      Component.of(
                        'games',
                        id: 'folder',
                        prefab: folderPrefabId,
                        x: 1,
                        y: 0,
                      ),
                      Component.of(
                        'clock',
                        id: 'clock',
                        prefab: 'clock',
                        w: 2,
                        x: 2,
                        y: 1,
                        overrides: const {
                          'date': {'hidden': true},
                        },
                      ),
                    ],
                  ),
                  Component.pane(id: 'main'),
                ],
                [
                  folderPane('games', title: 'Games')
                      .withOption('dock', 'bottom')
                      .withOption('height', 270)
                      .copyWith(children: [entity('pkg.b')]),
                ],
              ),
            ],
          ).normalised(),
        ),
      );
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget);
      // Beta is in the folder: only its picture shows, on the folder's face.
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsWidgets);

      // The folder is the first thing on screen, so it has the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsNWidgets(3));

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.b']);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('sections and entities are painted the way the user chose', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home([
                Component.pane(
                  id: 'main',
                  style: const {
                    'background': {
                      'colors': ['#3d5afecc', '#00000000'],
                      'angle': 90,
                    },
                    'borderColor': '#ffffff55',
                  },
                  children: [
                    const Component(
                      id: 'a',
                      prefab: cardPrefabId,
                      vars: {
                        'source': Variable('app:pkg.a', type: VarType.entity),
                      },
                      style: {'background': '#b71c1c'},
                    ),
                  ],
                ),
              ]),
            ],
          ).normalised(),
        ),
      );
      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .toList();
      final section = decorations.firstWhere((d) => d.gradient != null);
      final gradient = section.gradient! as LinearGradient;
      expect(gradient.colors, const [Color(0xCC3D5AFE), Color(0x00000000)]);
      // 90 degrees runs left to right.
      final begin = gradient.begin as Alignment,
          end = gradient.end as Alignment;
      expect((begin.x, end.x), (-1, 1));
      expect(begin.y, closeTo(0, 1e-9));
      // The outline is painted over the pane, by a decoration of its own.
      expect(
        decorations.map((d) => d.border?.top.color),
        contains(const Color(0x55FFFFFF)),
      );

      final entity = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Alpha').first,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (entity.decoration! as BoxDecoration).color,
        const Color(0xFFB71C1C),
      );
      // Still works as an entity.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.a']);
    });

    testWidgets('an entity can be shown without its name', (tester) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home([
                Component.pane(
                  id: 'main',
                  children: [
                    Component(
                      id: 'a',
                      prefab: cardPrefabId,
                      vars: {
                        'source': Variable('app:pkg.a', type: VarType.entity),
                      },
                      overrides: {
                        'name': {'hidden': true},
                      },
                    ),
                  ],
                ),
              ]),
            ],
          ).normalised(),
        ),
      );
      // Alpha has no icon here, so its name is still what its picture
      // shows; the label under it is not painted. Beta has both.
      expect(find.text('Alpha'), findsNWidgets(2));
      bool nameShown(String name) => tester
          .widget<Visibility>(
            find
                .ancestor(
                  of: find.text(name).last,
                  matching: find.byType(Visibility),
                )
                .first,
          )
          .visible;
      expect((nameShown('Alpha'), nameShown('Beta')), (false, true));
      expect(find.text('Beta'), findsNWidgets(2));
      // The picture is the size it would be with its name showing.
      Size picture(String name) => tester.getSize(
        find
            .ancestor(
              of: find.text(name).first,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(picture('Alpha'), picture('Beta'));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.a']);
    });

    testWidgets('a pane pads the same with or without a background', (
      tester,
    ) async {
      Component pane(String id, String package, Style style) => Component.pane(
        id: id,
        columns: 2,
        style: style,
        children: [entity(package)],
      );
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'plain',
            removed: const {'app:pkg.c', 'launcher:settings'},
            layers: [
              home([
                pane('plain', 'pkg.a', const {}),
                pane('painted', 'pkg.b', const {
                  'background': '#224466',
                  'borderColor': '#ffffff',
                }),
              ]),
            ],
          ).normalised(),
        ),
      );
      // The whole tile, which does not grow when focused as its picture does.
      Rect tile(String name) => tester.getRect(
        find
            .ancestor(
              of: find.text(name).first,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is ComponentView && widget.component.isInstance,
              ),
            )
            .first,
      );
      Rect box(String name) => tester.getRect(
        find
            .ancestor(of: find.text(name).first, matching: find.byType(PaneBox))
            .first,
      );
      // Beta's pane has a background and an outline; Alpha's has neither.
      // Each entity is the same size, the same distance in from its pane.
      final alpha = tile('Alpha'), beta = tile('Beta');
      expect(beta.width, closeTo(alpha.width, 1e-6));
      expect(beta.height, closeTo(alpha.height, 1e-6));
      for (final (entity, pane) in [
        (alpha, box('Alpha')),
        (beta, box('Beta')),
      ]) {
        expect(
          entity.left - pane.left,
          closeTo(Component.defaultPadding, 1e-6),
        );
        expect(entity.top - pane.top, closeTo(Component.defaultPadding, 1e-6));
      }
    });

    testWidgets('a pane too short for its entities shows their tops', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'short',
            removed: const {'app:pkg.c', 'launcher:settings'},
            layers: [
              Layer(
                id: Layout.homeId,
                root: Component.pane(
                  id: 'global',
                  mode: PaneMode.grid,
                  columns: 12,
                  children: [
                    // One row tall, but its two columns make entities far
                    // taller than that.
                    Component.pane(
                      id: 'short',
                      columns: 2,
                      children: [entity('pkg.a'), entity('pkg.b')],
                      x: 2,
                      y: 1,
                      w: 8,
                      h: 1,
                    ),
                  ],
                ),
              ),
            ],
          ).normalised(),
        ),
      );
      Rect of(Finder finder) => tester.getRect(finder.first);
      final pane = of(find.byType(PaneBox));
      Rect tile(String name) => of(
        find.ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate(
            (widget) => widget is ComponentView && widget.component.isInstance,
          ),
        ),
      );
      expect(tile('Alpha').height, greaterThan(pane.height));
      // Whichever has the focus, its top is inside the pane with room to
      // spare for the outline; it is the bottom that is cut.
      final resting = tile('Alpha').top;
      expect(resting - pane.top, greaterThanOrEqualTo(12));
      // Moving along the row, in either direction, the pane holds still
      // from the first frame to the last: no jump to the bottom and back.
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyEvent(key);
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tile('Alpha').top, resting);
          expect(tile('Beta').top, resting);
        }
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.b']);
    });

    testWidgets('a sidebar opens while the focus is in it', (tester) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [Component.pane(id: 'main')],
                [
                  sidebarPane(
                    'left',
                    'left',
                  ).copyWith(children: [entity('pkg.c')]),
                ],
              ),
            ],
          ).normalised(),
        ),
      );
      double railWidth() => tester
          .getSize(
            find
                .descendant(of: dock('left'), matching: find.byType(Container))
                .first,
          )
          .width;
      expect(dock('left'), findsOneWidget);
      // Closed, a strip of its pictures.
      expect(railWidth(), 96);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(railWidth(), 260);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.c']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(railWidth(), 96);
    });

    testWidgets('a sidebar opens the way it is set to', (tester) async {
      List<String> choices(String rule) => [
        ...dockRules(sidebarPane('left', 'left'))
            .firstWhere((option) => option.key == rule)
            .choices
            .keys,
      ];
      for (final opening in choices('opening')) {
        for (final reveal in choices('reveal')) {
          await pumpApp(
            tester,
            LauncherConfig(
              layout: Layout(
                inbox: 'main',
                layers: [
                  home(
                    [Component.pane(id: 'main')],
                    [
                      sidebarPane('left', 'left')
                          .withOption('opening', opening)
                          .withOption('reveal', reveal)
                          .copyWith(children: [entity('pkg.c')]),
                    ],
                  ),
                ],
              ).normalised(),
            ),
          );
          final box = find
              .descendant(of: dock('left'), matching: find.byType(Container))
              .first;
          // How solid what is in it is drawn; 1 with nothing fading it.
          double solid() => tester
              .widgetList<Opacity>(
                find.descendant(of: box, matching: find.byType(Opacity)),
              )
              .fold(1, (least, one) => min(least, one.opacity));
          final reason = '$opening, $reveal';
          expect(tester.getSize(box).width, 96, reason: reason);
          expect(solid(), reveal == 'always' ? 1 : 0, reason: reason);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
          expect(tester.getSize(box).width, 260, reason: reason);
          expect(solid(), 1, reason: reason);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(tester.getSize(box).width, 96, reason: reason);
          await tester.pumpWidget(const SizedBox());
        }
      }
    });

    testWidgets('a sidebar out of sight is reached at its edge', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [Component.pane(id: 'main')],
                [
                  sidebarPane(
                    'top',
                    'top',
                  ).copyWith(children: [entity('pkg.c')]),
                ],
              ),
            ],
          ).normalised(),
        ),
      );
      double barHeight() => tester
          .getSize(
            find
                .descendant(of: dock('top'), matching: find.byType(Container))
                .first,
          )
          .height;
      expect(barHeight(), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(barHeight(), 120);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.c']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(barHeight(), 0);
    });

    testWidgets('notifications pop up, unless switched off', (tester) async {
      await pumpApp(tester);
      platform.notify(
        AppNotification(
          packageName: 'pkg.a',
          appLabel: 'Alpha',
          title: 'Download finished',
          text: 'holiday.mkv',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Download finished'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('Download finished'), findsNothing);
    });
  });

  group('settings', () {
    late FakeLauncherPlatform platform;

    Future<void> openSettings(WidgetTester tester) async {
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
      ], [])..homeButtonEnabled = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configStoreProvider.overrideWithValue(MemoryConfigStore()),
            launcherPlatformProvider.overrideWithValue(platform),
            configServerProvider.overrideWith((ref) => null),
          ],
          child: const OpenLauncherApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set as Home'));
      await tester.pumpAndSettle();
    }

    testWidgets('automatic setup turns the Home button on', (tester) async {
      await openSettings(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Set up automatically'));
      await tester.pumpAndSettle();
      expect(find.text('All set'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Once set up, the switch works directly.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(platform.homeButtonEnabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // Back on the home screen the prompt is offered again.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Set as Home'), findsOneWidget);
    });

    testWidgets('explains what to do when debugging is off', (tester) async {
      await openSettings(tester);
      platform.setupOutcome = SetupOutcome.adbUnavailable;

      // Turning the switch on before setup runs setup.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('USB debugging is off'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(platform.homeButtonEnabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('re-checks the Home button when the app resumes', (
      tester,
    ) async {
      await openSettings(tester);
      // The user switches the service on in the TV's own settings.
      platform.homeButtonEnabled = true;
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });
}
