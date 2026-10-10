import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/sidebar.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

void main() {
  testWidgets('shows app cards and launches with the D-pad', (tester) async {
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

    // First card has focus on start; D-pad centre launches it.
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

    /// A home screen of [panes] one under another, each five rows tall,
    /// with room on the left for a rail.
    Panel home(List<Pane> panes) => Panel(
      id: Layout.homeId,
      root: Pane(
        id: 'global',
        mode: PaneMode.grid,
        columns: 12,
        items: [
          for (final (index, pane) in panes.indexed)
            LayoutItem.pane(pane, x: 2, y: index * 5, w: 10, h: 5),
        ],
      ),
    );

    LayoutItem card(String package) =>
        LayoutItem(id: 'i-$package', kind: ItemKind.card, ref: 'app:$package');

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

    testWidgets('a folder opens a popup that closes when a card is opened', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              home([
                Pane(
                  id: 'top',
                  title: 'Favourites',
                  mode: PaneMode.grid,
                  columns: 4,
                  items: [
                    const LayoutItem(
                      id: 'folder',
                      kind: ItemKind.panel,
                      ref: 'games',
                      x: 1,
                      y: 0,
                    ),
                    const LayoutItem(
                      id: 'clock',
                      kind: ItemKind.widget,
                      ref: 'clock',
                      w: 2,
                      x: 2,
                      y: 1,
                      options: {'date': false},
                    ),
                  ],
                ),
                const Pane(id: 'main'),
              ]),
              Panel(
                id: 'games',
                title: 'Games',
                position: PopupPosition.bottom,
                root: Pane(id: 'in', items: [card('pkg.b')]),
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

    testWidgets('sections and cards are painted the way the user chose', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              home([
                Pane(
                  id: 'main',
                  style: const BoxStyle(
                    colors: [0xCC3D5AFE, 0x00000000],
                    angle: 90,
                    border: 0x55FFFFFF,
                  ),
                  items: [
                    const LayoutItem(
                      id: 'a',
                      kind: ItemKind.card,
                      ref: 'app:pkg.a',
                      style: BoxStyle(colors: [0xFFB71C1C]),
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

      final card = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Alpha').first,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (card.decoration! as BoxDecoration).color,
        const Color(0xFFB71C1C),
      );
      // Still works as a card.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.a']);
    });

    testWidgets('a card can be shown without its name', (tester) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              home([
                const Pane(
                  id: 'main',
                  items: [
                    LayoutItem(
                      id: 'a',
                      kind: ItemKind.card,
                      ref: 'app:pkg.a',
                      hideName: true,
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
      Pane pane(String id, String package, BoxStyle style) =>
          Pane(id: id, columns: 2, style: style, items: [card(package)]);
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'plain',
            removed: const {'app:pkg.c', 'launcher:settings'},
            panels: [
              home([
                pane('plain', 'pkg.a', BoxStyle.none),
                pane(
                  'painted',
                  'pkg.b',
                  const BoxStyle(colors: [0xFF224466], border: 0xFFFFFFFF),
                ),
              ]),
            ],
          ).normalised(),
        ),
      );
      // The whole tile, which does not grow when focused as its picture does.
      Rect tile(String name) => tester.getRect(
        find
            .ancestor(of: find.text(name).first, matching: find.byType(ArtTile))
            .first,
      );
      Rect box(String name) => tester.getRect(
        find
            .ancestor(of: find.text(name).first, matching: find.byType(PaneBox))
            .first,
      );
      // Beta's pane has a background and an outline; Alpha's has neither.
      // Each card is the same size, the same distance in from its pane.
      final alpha = tile('Alpha'), beta = tile('Beta');
      expect(beta.width, closeTo(alpha.width, 1e-6));
      expect(beta.height, closeTo(alpha.height, 1e-6));
      for (final (card, pane) in [(alpha, box('Alpha')), (beta, box('Beta'))]) {
        expect(card.left - pane.left, closeTo(Pane.defaultPadding, 1e-6));
        expect(card.top - pane.top, closeTo(Pane.defaultPadding, 1e-6));
      }
    });

    testWidgets('a pane too short for its cards shows their tops', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'short',
            removed: const {'app:pkg.c', 'launcher:settings'},
            panels: [
              Panel(
                id: Layout.homeId,
                root: Pane(
                  id: 'global',
                  mode: PaneMode.grid,
                  columns: 12,
                  items: [
                    // One row tall, but its two columns make cards far
                    // taller than that.
                    LayoutItem.pane(
                      Pane(
                        id: 'short',
                        columns: 2,
                        items: [card('pkg.a'), card('pkg.b')],
                      ),
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
        find.ancestor(of: find.text(name), matching: find.byType(ArtTile)),
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
            panels: [
              home([const Pane(id: 'main')]),
              Panel.empty(Layout.leftId).withRoot(
                Panel.empty(Layout.leftId).root.withItems([card('pkg.c')]),
              ),
            ],
          ).normalised(),
        ),
      );
      double railWidth() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Sidebar),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .width;
      expect(find.byType(Sidebar), findsOneWidget);
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

    testWidgets('a sidebar out of sight is reached at its edge', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              home([const Pane(id: 'main')]),
              Panel.empty(Layout.topId).withRoot(
                Panel.empty(Layout.topId).root.withItems([card('pkg.c')]),
              ),
            ],
          ).normalised(),
        ),
      );
      double barHeight() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Sidebar),
                  matching: find.byType(AnimatedContainer),
                )
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
