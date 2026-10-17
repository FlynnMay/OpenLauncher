import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/app.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/docked_pane.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

import '../support/packs.dart';

/// Panes drawn as nodes, nearest first.
final _panel = find.byWidgetPredicate(
  (widget) => widget is NodeView && widget.component.isPane,
);

void main() {
  testWidgets('shows app entities and launches with the D-pad', (tester) async {
    final platform = FakeLauncherPlatform([
      InstalledApp(packageName: 'pkg.a', label: 'Alpha', isBanner: false),
      InstalledApp(packageName: 'pkg.b', label: 'Beta', isBanner: false),
    ], []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(startingConfig),
          ),
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
            ...packOverrides,
            configStoreProvider.overrideWithValue(
              MemoryConfigStore(config ?? startingConfig),
            ),
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
    Layer home(List<Node> panes, [List<Node> docked = const []]) => Layer(
      id: Layout.homeId,
      root: Node.pane(
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

    Node entity(String package) =>
        cardOf('system:app/$package', id: 'i-$package');

    testWidgets('holding OK offers quick actions instead of opening', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(FocusTile.holdTime);
      await tester.pumpAndSettle();
      expect(find.text('App info'), findsOneWidget);

      // The button is still down: holding on and letting go choose nothing.
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('App info'), findsOneWidget);
      expect(platform.launched, isEmpty);

      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.appActions, ['uninstall pkg.a']);
      expect(find.text('App info'), findsNothing);
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
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('App info'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsWidgets);
    });

    testWidgets('a menu goes by its entity variable, whatever its name', (
      tester,
    ) async {
      Node button(String label, String action) => Node(
        id: 'pick-$action',
        prefab: 'system:button',
        modules: {
          variablesModule.name: {'label': label},
          triggersModule.name: triggersToJson({
            Trigger.press: [
              Act(action, {'entity': '{{target.id}}'}),
            ],
          }),
        },
      );
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [Node.pane(id: 'main')],
                [
                  folderPane('pick')
                      .withVars(const {
                        'target': Variable(null, type: VarType.entity),
                      })
                      .copyWith(
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
      await openFor('system:clock');
      expect(find.text('Start it'), findsNothing);

      // An app has nothing to play.
      await openFor('system:app/pkg.a');
      expect(find.text('Start it'), findsOneWidget);
      expect(find.text('Play it'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.a']);
      expect(find.text('Start it'), findsNothing);
    });

    testWidgets('children of a node that draws are placed over it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home([
                Node.pane(
                  id: 'main',
                  children: [
                    drawn(
                      'cover',
                      pictureModule.name,
                      values: const {'alt': 'Cover'},
                      w: 2,
                      h: 2,
                    ).copyWith(
                      children: const [
                        Node(
                          id: 'tag',
                          transform: NodeTransform(minX: 0.5, minY: 0.5),
                          modules: {
                            'text': {'text': 'NEW'},
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ],
          ).normalised(),
        ),
      );
      final cover = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is NodeView && widget.component.id == 'cover',
        ),
      );
      final tag = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is NodeView && widget.component.id == 'tag',
        ),
      );
      expect(find.text('Cover'), findsOneWidget);
      expect(tag.topLeft, cover.center);
      expect(tag.bottomRight, cover.bottomRight);
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
                  Node.pane(
                    id: 'top',
                    name: 'Favourites',
                    mode: PaneMode.grid,
                    columns: 4,
                    children: [
                      cardOf(
                        'games',
                        id: 'folder',
                        prefab: folderPrefabId,
                        x: 1,
                        y: 0,
                      ),
                      cardOf(
                        'system:clock',
                        id: 'system:clock',
                        prefab: 'system:clock',
                        w: 2,
                        x: 2,
                        y: 1,
                        overrides: const {
                          'date': {'hidden': true},
                        },
                      ),
                    ],
                  ),
                  Node.pane(id: 'main'),
                ],
                [
                  folderPane('games', title: 'Games')
                      .withValue(dockModule.name, 'position', 'bottom')
                      .withValue(dockModule.name, 'height', 270)
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
                Node.pane(
                  id: 'main',
                  style: const {
                    'background': {
                      'colors': ['#3d5afecc', '#00000000'],
                      'angle': 90,
                    },
                    'borderColor': '#ffffff55',
                  },
                  children: [
                    cardOf(
                      'system:app/pkg.a',
                      id: 'a',
                      style: const {'background': '#b71c1c'},
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
                Node.pane(
                  id: 'main',
                  children: [
                    cardOf(
                      'system:app/pkg.a',
                      id: 'a',
                      overrides: const {
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
      Node pane(String id, String package, Style style) => Node.pane(
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
            removed: const {'system:app/pkg.c', 'system:settings'},
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
                (widget) => widget is NodeView && widget.component.isInstance,
              ),
            )
            .first,
      );
      Rect box(String name) => tester.getRect(
        find.ancestor(of: find.text(name).first, matching: _panel).first,
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
          closeTo(LayoutModule.defaultPadding, 1e-6),
        );
        expect(
          entity.top - pane.top,
          closeTo(LayoutModule.defaultPadding, 1e-6),
        );
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
            removed: const {'system:app/pkg.c', 'system:settings'},
            layers: [
              Layer(
                id: Layout.homeId,
                root: Node.pane(
                  id: 'global',
                  mode: PaneMode.grid,
                  columns: 12,
                  children: [
                    // One row tall, but its two columns make entities far
                    // taller than that.
                    Node.pane(
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
      final pane = of(_panel);
      Rect tile(String name) => of(
        find.ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate(
            (widget) => widget is NodeView && widget.component.isInstance,
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

    testWidgets('a pane scrolls the ways it is set to', (tester) async {
      Future<void> pump([Map<String, Object?>? scroll]) => pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'p',
            removed: const {'system:settings'},
            layers: [
              home([
                Node.pane(
                  id: 'p',
                  columns: 2,
                  scroll: scroll,
                  children: [entity('pkg.a'), entity('pkg.b'), entity('pkg.c')],
                ),
              ]),
            ],
          ).normalised(),
        ),
      );
      Rect of(Finder finder) => tester.getRect(finder.first);
      Rect tile(String name) => of(
        find.ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate(
            (widget) => widget is NodeView && widget.component.isInstance,
          ),
        ),
      );
      Iterable<Axis> scrolls() => tester
          .widgetList<SingleChildScrollView>(
            find.descendant(
              of: _panel,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .map((view) => view.scrollDirection);

      // As it comes: wrapped at its columns, scrolling down.
      await pump();
      expect(scrolls(), [Axis.vertical]);
      expect(tile('Gamma').top, greaterThan(tile('Alpha').top));
      expect(tile('Gamma').left, tile('Alpha').left);

      // Across: one row, its cells no narrower, the third out of sight until
      // the focus gets there.
      final cell = tile('Alpha').size;
      await pump(const {'across': true});
      await tester.pumpAndSettle();
      expect(scrolls(), [Axis.horizontal]);
      final pane = of(_panel);
      expect(tile('Alpha').size, cell);
      expect(tile('Gamma').top, tile('Alpha').top);
      expect(tile('Gamma').left, greaterThan(pane.right - 20));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tile('Gamma').right, lessThan(pane.right));
      expect(tile('Alpha').left, lessThan(pane.left));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(platform.launched, ['pkg.c']);

      // Neither: nothing in it scrolls.
      await pump(const {});
      await tester.pumpAndSettle();
      expect(scrolls(), isEmpty);
      expect(tile('Gamma').top, greaterThan(tile('Alpha').top));
    });

    test('cells measure the same from the whole grid as from the pane', () {
      final pane = Node.pane(
        id: 'p',
        columns: 2,
        scroll: const {'across': true},
        children: [entity('pkg.a'), entity('pkg.b'), entity('pkg.c')],
      );
      final shown = PaneMetrics.shown(pane, 400);
      // The editor has only the grid's own box, three columns wide here.
      final whole = PaneMetrics(pane, shown.across(3));
      expect(whole.cellWidth, closeTo(shown.cellWidth, 1e-9));
      expect(
        shown.cellWidth,
        PaneMetrics(
          pane.withValue(scrollModule.name, 'across', null),
          400,
        ).cellWidth,
      );
    });

    test('a scroll bar is placed by how far the pane is scrolled', () {
      ScrollMetrics at(
        double pixels, [
        AxisDirection direction = AxisDirection.down,
      ]) => FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 300,
        pixels: pixels,
        viewportDimension: 100,
        axisDirection: direction,
        devicePixelRatio: 1,
      );
      const box = Size(200, 108);
      const look = ScrollbarStyle();
      // A quarter is in view: a thumb a quarter of the track, at the right.
      final top = barRects(box, at(0), look)!;
      expect(top.track, const Rect.fromLTRB(190, 4, 196, 104));
      expect(top.thumb, const Rect.fromLTRB(190, 4, 196, 29));
      expect(barRects(box, at(150), look)!.thumb.top, 41.5);
      expect(barRects(box, at(300), look)!.thumb.bottom, 104);
      // Past either end it stays on its track.
      expect(barRects(box, at(-40), look)!.thumb, top.thumb);
      // No shorter than its least, and inside the track's sides.
      final small = barRects(
        box,
        at(0),
        const ScrollbarStyle(minLength: 40, inset: 1, start: true),
      )!;
      expect(small.thumb, const Rect.fromLTRB(5, 5, 9, 45));

      // Progress fills from the start, and its gradient spans the whole.
      final half = barRects(box, at(150), look, progress: true)!;
      expect(half.thumb, const Rect.fromLTRB(190, 4, 196, 54));
      expect(half.travel, half.track);
      expect(barRects(box, at(0), look, progress: true)!.thumb.height, 0);

      // Across, at the bottom; mirrored, it starts from the right. With one
      // each way the corner is left free.
      final across = barRects(box, at(0, AxisDirection.right), look)!;
      expect(across.track, const Rect.fromLTRB(4, 98, 196, 104));
      expect(across.thumb.left, 4);
      expect(barRects(box, at(0, AxisDirection.left), look)!.thumb.right, 196);
      expect(
        barRects(box, at(0, AxisDirection.right), look, both: true)!.track,
        const Rect.fromLTRB(4, 98, 186, 104),
      );
      // Half the edge, in its middle.
      expect(
        barRects(box, at(0), const ScrollbarStyle(length: 0.5))!.track,
        const Rect.fromLTRB(190, 29, 196, 79),
      );
      // Nothing to scroll, nothing to show.
      expect(
        barRects(
          box,
          FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 0,
            pixels: 0,
            viewportDimension: 100,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          look,
        ),
        isNull,
      );
    });

    testWidgets('a pane draws the scroll bar it is given', (tester) async {
      Future<void> pump(
        Map<String, Object?> rules, [
        Map<String, Object?> style = const {},
      ]) async {
        // Each from the start: nothing scrolled, the first tile focused.
        await tester.pumpWidget(const SizedBox());
        await pumpApp(
          tester,
          LauncherConfig(
            layout: Layout(
              inbox: 'p',
              removed: const {'system:settings'},
              layers: [
                home([
                  Node.pane(
                    id: 'p',
                    columns: 2,
                    scroll: {'across': true, ...rules, ...style},
                    children: [
                      entity('pkg.a'),
                      entity('pkg.b'),
                      entity('pkg.c'),
                    ],
                  ),
                ]),
              ],
            ).normalised(),
          ),
        );
      }

      final bars = find.byType(PaneScrollbars);
      final paint = find.descendant(
        of: bars,
        matching: find.byType(CustomPaint),
      );
      await pump(const {});
      expect(bars, findsNothing);

      // Two of three columns in view: a thumb two thirds of the track.
      await pump(
        const {'bar': 'thumb'},
        const {'scrollbarThumb': '#ff0000', 'scrollbarSize': 10},
      );
      await tester.pumpAndSettle();
      final box = tester.getSize(bars);
      final track = box.width - 8;
      RRect bar(double left, double width) => RRect.fromRectAndRadius(
        Rect.fromLTWH(left, box.height - 14, width, 10),
        const Radius.circular(5),
      );
      const red = Color(0xFFFF0000);
      final view = tester.getSize(
        find.descendant(of: bars, matching: find.byType(SingleChildScrollView)),
      );
      final grid = tester.getSize(find.byType(PaneScope).last);
      final thumb = track * view.width / grid.width;
      expect(thumb, closeTo(track * 2 / 3, 8));
      expect(paint, paints..rrect(rrect: bar(4, thumb), color: red));
      // No track unless it is given one.
      expect(paint, paintsExactlyCountTimes(#drawRRect, 1));
      // At the far end once the focus is there.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        paint,
        paints..rrect(rrect: bar(4 + track - thumb, thumb), color: red),
      );
      expect(tester.takeException(), isNull);

      // Progress: a track, and a fill that is all of it at the end.
      await pump(
        const {'bar': 'progress'},
        const {'scrollbarThumb': '#ff0000', 'scrollbarSize': 10},
      );
      await tester.pumpAndSettle();
      expect(paint, paints..rrect(rrect: bar(4, track)));
      expect(paint, paintsExactlyCountTimes(#drawRRect, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        paint,
        paints
          ..rrect(rrect: bar(4, track))
          ..rrect(rrect: bar(4, track), color: red),
      );

      // One that hides is gone a while after the last movement.
      await pump(const {'bar': 'thumb', 'show': 'auto'});
      double shown() => tester
          .widget<FadeTransition>(
            find.descendant(of: bars, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value;
      expect(shown(), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(shown(), 1);
      await tester.pumpAndSettle();
      expect(shown(), 0);
    });

    testWidgets('a row scrolls along itself when set to', (tester) async {
      Node label(String id) => drawn(
        id,
        textModule.name,
        values: {'text': id},
        on: {
          Trigger.press: const [
            Act('open', {'entity': 'system:app/pkg.a'}),
          ],
        },
      );
      Future<void> pump(Map<String, Object?> rules) => pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'global',
            removed: const {
              'system:app/pkg.a',
              'system:app/pkg.b',
              'system:app/pkg.c',
              'system:settings',
            },
            layers: [
              Layer(
                id: Layout.homeId,
                root: Node.pane(
                  id: 'global',
                  mode: PaneMode.grid,
                  columns: 12,
                  children: [
                    Node.pane(
                      id: 'line',
                      mode: PaneMode.row,
                      layout: const {'gap': 400},
                      scroll: rules,
                      children: [
                        for (final id in ['one', 'two', 'three', 'four'])
                          label(id),
                      ],
                      x: 2,
                      y: 1,
                      w: 4,
                      h: 1,
                    ),
                  ],
                ),
              ),
            ],
          ).normalised(),
        ),
      );
      final line = find.byWidgetPredicate(
        (widget) => widget is NodeView && widget.component.id == 'line',
      );
      Finder scroll() => find.descendant(
        of: line,
        matching: find.byType(SingleChildScrollView),
      );
      await pump(const {'across': true});
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<SingleChildScrollView>(scroll()).scrollDirection,
        Axis.horizontal,
      );
      final box = tester.getRect(line);
      expect(tester.getRect(find.text('four')).left, greaterThan(box.right));
      for (var step = 0; step < 3; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      // At the end of the row, with only its focused growth past the box.
      expect(
        tester.getRect(find.text('four')).right,
        lessThan(box.right + overhang),
      );
      expect(tester.getRect(find.text('one')).right, lessThan(box.left));
    });

    testWidgets('a sidebar opens while the focus is in it', (tester) async {
      await pumpApp(
        tester,
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            layers: [
              home(
                [Node.pane(id: 'main')],
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
        ...dockModule.fields
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
                    [Node.pane(id: 'main')],
                    [
                      sidebarPane('left', 'left')
                          .withValue(dockModule.name, 'opening', opening)
                          .withValue(dockModule.name, 'reveal', reveal)
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
                [Node.pane(id: 'main')],
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
      ], [])..access[Access.homeButton] = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...packOverrides,
            configStoreProvider.overrideWithValue(
              MemoryConfigStore(startingConfig),
            ),
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

    /// What the row for [access] says of it.
    String standing(WidgetTester tester, Access access) {
      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, access.label),
      );
      return (row.trailing! as Text).data!;
    }

    testWidgets('each permission is changed on the TV\'s own screen', (
      tester,
    ) async {
      await openSettings(tester);
      expect(standing(tester, Access.homeButton), 'Not allowed');
      expect(standing(tester, Access.notifications), 'Allowed');

      await tester.tap(find.text(Access.homeButton.label));
      await tester.tap(find.text(Access.notifications.label));
      await tester.pumpAndSettle();
      expect(platform.accessChanged, Access.values);
      // Nothing is claimed until the TV says so.
      expect(standing(tester, Access.homeButton), 'Not allowed');
    });

    testWidgets('says so when the TV has no screen for a permission', (
      tester,
    ) async {
      await openSettings(tester);
      platform.noAccessScreen = true;
      await tester.tap(find.text(Access.homeButton.label));
      await tester.pumpAndSettle();
      expect(find.text('This TV has no screen for it'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(platform.accessChanged, isEmpty);
    });

    testWidgets('re-checks the Home button when the app resumes', (
      tester,
    ) async {
      await openSettings(tester);
      // The user switches the service on in the TV's own settings.
      platform.access[Access.homeButton] = true;
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
      expect(standing(tester, Access.homeButton), 'Allowed');
    });
  });
}
