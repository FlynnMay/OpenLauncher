import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/panels/panels.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';

import '../support/packs.dart';

class _Tv extends TvApi {
  @override
  Future<void> setLayout(Layout layout) async {}

  @override
  Future<void> setConfig(Map<String, Object?> changed) async {}
}

const _entity = Entity(
  id: 'system:app/a',
  category: appCategory,
  label: 'Alpha',
);

void main() {
  Future<WidgetRef> pump(
    WidgetTester tester,
    Size size, {
    TvState? state,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          systemContents,
          tvApiProvider.overrideWithValue(_Tv()),
          tvStateProvider.overrideWith(
            (ref) => Stream.value(
              state ??
                  TvState(
                    packs: [systemPack],
                    entities: const [_entity],
                    config: LauncherConfig(
                      layout: homeLayout(['system:app/a']),
                    ),
                    components: const [],
                  ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const EditorScreen();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ref;
  }

  Finder inTree(String label) =>
      find.descendant(of: find.byType(ObjectTree), matching: find.text(label));

  testWidgets('a press in the list of objects picks the thing out', (
    tester,
  ) async {
    final ref = await pump(tester, const Size(1600, 900));
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    expect(inTree('Home screen'), findsOneWidget);

    await tester.tap(inTree('Alpha'));
    await tester.pumpAndSettle();
    final picked = ref.read(selectedProvider).single;
    expect(picked.item.handed.firstOrNull, 'system:app/a');

    // Its id is beside its name, and a press copies it.
    final id = find.text('(ID: ${picked.item.id})');
    expect(id, findsOneWidget);
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      },
    );
    await tester.tap(id);
    await tester.pumpAndSettle();
    expect(copied, [
      {'text': picked.item.id},
    ]);

    await tester.tap(inTree('Home screen'));
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), isEmpty);
  });

  testWidgets('Delete in a text box is typing, not removing', (tester) async {
    final ref = await pump(tester, const Size(1600, 900));
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(inTree('Alpha'));
    await tester.pumpAndSettle();
    final box = find.descendant(
      of: find.byType(Inspector),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(box.first);
    await tester.tap(box.first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), isNotEmpty);
    expect(inTree('Alpha'), findsOneWidget);
  });

  testWidgets('under a narrow screen the three take turns', (tester) async {
    await pump(tester, const Size(420, 900));
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(inTree('Alpha'));
    await tester.pumpAndSettle();
    // Picking something out brings up its settings.
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Multi-select').hitTestable(), findsOneWidget);
  });

  testWidgets('a sidebar is only taken by an edge that has none', (
    tester,
  ) async {
    final ref = await pump(tester, const Size(1600, 900));
    Layout layout() => ref.read(configProvider).value!.layout;
    final screen = tester.getRect(find.byType(TvScreen));

    Future<void> drag(Offset to) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Sidebar')),
      );
      // Held, as a finger has to before it picks something up.
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveTo(screen.center);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // In the middle of the screen it goes nowhere.
    await drag(screen.center);
    expect(freeEdges(layout()), barEdges);
    expect(ref.read(selectionProvider), isEmpty);

    await drag(screen.centerLeft + const Offset(10, 0));
    // Selected, so it is held open and its settings show.
    expect(ref.read(selectionProvider), {'left'});
    final left = layout().pane('left')!;
    expect((left.dock, left.hovers), ('left', false));

    // It is an object like any other: let go of, the launcher's settings
    // show, which have no section for sidebars; picked out of the list, its
    // own do, as a pane's with where it is docked.
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(inTree('Home screen'));
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), isEmpty);
    expect(find.text('Sidebars'), findsNothing);
    await tester.tap(inTree('Left sidebar'));
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), {'left'});
    expect(find.text('Dock'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Collapsed size'), findsOneWidget);
    expect(find.text('Transform'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('what can be added is under headings that close', (tester) async {
    const mine = Entity(
      id: 'mine',
      category: 'mine',
      label: 'Mine',
      prefab: cardPrefabId,
    );
    await pump(
      tester,
      const Size(1600, 1400),
      state: TvState(
        packs: [systemPack],
        entities: const [
          Entity(
            id: 'system:app/a',
            category: appCategory,
            label: 'Alpha',
            prefab: cardPrefabId,
          ),
          Entity(
            id: 'system:app/b',
            category: appCategory,
            label: 'Beta',
            prefab: cardPrefabId,
          ),
          Entity(
            id: 'system:clock',
            category: 'clock',
            label: 'Clock',
            prefab: 'system:clock',
          ),
          mine,
        ],
        config: LauncherConfig(
          layout: homeLayout(['system:app/a']),
          entities: const [mine],
          prefabs: [
            Prefab(
              id: 'own',
              name: 'My prefab',
              root: Component.pane(id: 'root'),
            ),
            // The System pack's, edited: offered as the System pack's.
            Prefab(
              id: 'system:clock',
              name: 'Edited clock',
              root: Component.pane(
                id: 'root',
                vars: const {'clock': Variable(null, type: VarType.entity)},
              ),
            ),
          ],
        ),
        components: const [
          (type: 'button', label: 'Button', w: 2, h: 1, options: {}),
        ],
      ),
    );
    Finder offered(String label) =>
        find.descendant(of: find.byType(Catalogue), matching: find.text(label));
    // Each pack's things under its name, as a tree.
    const headings = [
      'Primitives',
      'System',
      'Templates',
      'Prefabs',
      'Entities',
      'Apps',
      'User prefabs',
    ];
    // The heading [label] is under.
    String over(String label) {
      // A card with no picture says its name twice.
      final top = tester.getTopLeft(offered(label).last).dy;
      return headings.lastWhere(
        (heading) => tester.getTopLeft(offered(heading)).dy < top,
      );
    }

    final tops = [
      for (final heading in headings) tester.getTopLeft(offered(heading)).dy,
    ];
    expect(tops, [...tops]..sort());
    for (final gone in ['Components', 'Buttons', 'Folders']) {
      expect(offered(gone), findsNothing);
    }
    expect(over('Button'), 'Primitives');
    expect(over('Pane'), 'Primitives');
    expect(over('Sidebar'), 'Templates');
    expect(over('Folder'), 'Templates');
    expect(find.byTooltip('Made from the Folder template'), findsOneWidget);
    // The only one of its category.
    expect(over('Clock'), 'Entities');
    expect(over('Edited clock'), 'Prefabs');
    expect(over('My prefab'), 'User prefabs');
    expect(over('Mine'), 'User prefabs');
    expect(over('Beta'), 'Apps');

    await tester.tap(offered('Apps'));
    await tester.pumpAndSettle();
    expect(offered('Beta'), findsNothing);
    expect(offered('Clock'), findsWidgets);
    // Closing the pack closes all of it.
    await tester.tap(offered('System'));
    await tester.pumpAndSettle();
    expect(offered('Templates'), findsNothing);
    expect(offered('Clock'), findsNothing);
    expect(offered('My prefab'), findsOneWidget);

    // A search shows what matches, closed or not.
    final search = find.descendant(
      of: find.byType(Catalogue),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'bet');
    await tester.pumpAndSettle();
    expect(offered('Beta'), findsWidgets);
    expect(offered('Primitives'), findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(offered('Beta'), findsNothing);
    await tester.tap(offered('System'));
    await tester.pumpAndSettle();
    // What was closed inside it stays closed.
    expect(offered('Clock'), findsWidgets);
    expect(offered('Beta'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
