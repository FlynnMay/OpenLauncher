import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/panels/panels.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';

import '../support/packs.dart';

class _Tv extends TvApi {
  @override
  Future<void> setLayout(Layout layout) async {}

  @override
  Future<void> setConfig(Map<String, Object?> changed) async {}
}

const _alpha = Entity(
  id: 'system:app/a',
  category: appCategory,
  label: 'Alpha',
  prefab: cardPrefabId,
  placed: true,
);

void main() {
  Future<WidgetRef> pump(WidgetTester tester, {LauncherConfig? config}) async {
    tester.view.physicalSize = const Size(1600, 1200);
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
              TvState(
                packs: [systemPack],
                entities: const [_alpha],
                config:
                    config ??
                    LauncherConfig(layout: homeLayout(['system:app/a'])),
                visuals: const [
                  (module: 'text', label: 'Text', w: 2, h: 1, values: {}),
                ],
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
  Finder onStage(String label) => find.descendant(
    of: find.byType(PrefabScreen),
    matching: find.text(label),
  );

  Future<void> press(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await tester.pumpAndSettle();
    await tester.tap(what);
    await tester.pumpAndSettle();
  }

  testWidgets('a prefab is opened and edited with the editor\'s own tools', (
    tester,
  ) async {
    final ref = await pump(tester);
    Prefab card() => ref
        .read(configProvider)
        .value!
        .prefabs
        .singleWhere((prefab) => prefab.id == cardPrefabId);

    // From the list in the launcher's settings.
    await press(
      tester,
      find.descendant(
        of: find.byType(PrefabList),
        matching: find.text('Prefabs'),
      ),
    );
    // The app card and the quick actions.
    expect(find.text('1 instance · System'), findsNWidgets(2));
    await press(
      tester,
      find.descendant(
        of: find.byType(PrefabList),
        matching: find.byTooltip('Open App card'),
      ),
    );
    expect(find.byType(PrefabScreen), findsOneWidget);
    expect(find.byType(TvScreen), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PrefabBar),
        matching: find.text('App card'),
      ),
      findsOneWidget,
    );
    // Drawn with the first thing that uses it; nothing is saved by looking.
    // (Its picture has none to show and says the name too.)
    expect(onStage('Alpha'), findsNWidgets(2));
    expect(ref.read(configProvider).value!.prefabs, isEmpty);

    // With nothing selected the prefab and its root show: its variables can
    // be kept off instances.
    expect(find.byType(PrefabDetails), findsOneWidget);
    expect(find.text('Variables'), findsOneWidget);

    // Its parts are in the list by id, and on the screen to press.
    await press(tester, find.text('Objects'));
    for (final id in ['root', 'picture', 'name']) {
      expect(inTree(id), findsOneWidget);
    }
    await tester.tap(onStage('Alpha').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), {'name'});
    expect(find.text('Visibility'), findsOneWidget);
    // A press on the prefab did not open the app.
    expect(tester.takeException(), isNull);

    // Something added goes into it, under an id free among its parts.
    await press(tester, find.text('Add'));
    expect(find.text('Sidebar'), findsNothing);
    expect(find.text('New folder'), findsNothing);
    await press(
      tester,
      find.descendant(of: find.byType(Catalogue), matching: find.text('Text')),
    );
    expect(card().root.children.map((part) => part.id), [
      'picture',
      'name',
      'text',
    ]);

    // Under another variant, an edit is that variant's override. This one
    // is for a sidebar's row, and is drawn in one.
    ref.read(prefabTrailProvider.notifier).drawAt(36);
    ref.read(prefabTrailProvider.notifier).show('row');
    await tester.pumpAndSettle();
    await press(tester, find.text('Objects'));
    await press(tester, inTree('name'));
    expect(find.text('Variant overrides'), findsOneWidget);
    await press(tester, find.text('Visible'));
    expect(card().variants['row']!.overrides['name']!['hidden'], true);
    expect(card().root.children.every((part) => !part.hidden), isTrue);
    expect(inTree('Text · hidden'), findsOneWidget);
    // Which is listed, and can be handed back.
    await press(tester, find.byTooltip('Revert').last);
    expect(
      card().variants['row']!.overrides['name']!.containsKey('hidden'),
      isFalse,
    );
    // What a variant cannot hold is refused.
    await press(tester, find.text('Add'));
    await press(
      tester,
      find.descendant(of: find.byType(Catalogue), matching: find.text('Text')),
    );
    expect(find.textContaining('Variants share'), findsOneWidget);
    expect(card().root.children, hasLength(3));

    // Another variant made the default becomes the tree; the rest look as
    // they did, as overrides on it.
    final stacked = card().rootAs('stacked').toJson();
    final row = card().rootAs('row').toJson();
    await makeDefaultVariant(ref, 'row');
    await tester.pumpAndSettle();
    expect(card().variants.keys, ['row', 'stacked']);
    expect(card().isBase('row'), isTrue);
    expect(card().root.toJson(), row);
    expect(card().rootAs('stacked').toJson(), stacked);
    // And back again.
    await makeDefaultVariant(ref, 'stacked');
    await tester.pumpAndSettle();
    expect(card().variants.keys, ['stacked', 'row']);
    expect(card().root.toJson(), stacked);
    expect(card().rootAs('row').toJson(), row);

    // And back to the home screen, where its instance follows.
    await press(tester, find.byTooltip('Back to the home screen'));
    expect(find.byType(TvScreen), findsOneWidget);
    expect(ref.read(prefabModeProvider), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the quick actions open where they show, to be edited', (
    tester,
  ) async {
    final ref = await pump(tester);
    openPrefab(ref, 'system:quick-actions');
    await tester.pumpAndSettle();
    // Open in the middle, as for the first thing on the screen.
    for (final label in ['Alpha', 'Open', 'App info', 'Uninstall', 'Remove']) {
      expect(onStage(label), findsOneWidget, reason: label);
    }
    await tester.tap(onStage('App info'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), {'info'});
    // Still open with one of its buttons selected.
    expect(onStage('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folder is an instance its prefab reaches', (tester) async {
    final ref = await pump(
      tester,
      config: LauncherConfig(
        layout: homeLayout(['system:app/a']).withPane(
          'home/root',
          (root) => root.copyWith(
            children: [
              ...root.children,
              folderPane('games', title: 'Games'),
            ],
          ),
        ),
      ),
    );
    await press(
      tester,
      find.descendant(
        of: find.byType(PrefabList),
        matching: find.text('Prefabs'),
      ),
    );
    expect(find.text('1 instance · System'), findsWidgets);
    openPrefab(ref, 'system:folder');
    await tester.pumpAndSettle();
    expect(find.textContaining('Template'), findsNothing);
    final games = ref
        .read(configProvider)
        .value!
        .layout
        .all
        .singleWhere((node) => node.id == 'games');
    expect(drawnPane(games).style, systemPrefab(folderId).root.style);
    expect(drawnPane(games).name, 'Games');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pane is made a prefab; deleting it unpacks the instance', (
    tester,
  ) async {
    final ref = await pump(tester);
    LauncherConfig config() => ref.read(configProvider).value!;
    await press(tester, find.text('Objects'));
    await press(tester, inTree('Pane'));
    await press(tester, find.text('Create prefab'));
    await tester.enterText(find.byType(TextField).last, 'Shelf');
    await press(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(config().prefabs.single.id, 'shelf');
    expect(config().prefabs.single.root.children.single.handed, [
      'system:app/a',
    ]);
    final instance = config().layout.all.singleWhere(
      (item) => item.prefab == 'shelf',
    );
    expect((instance.id, instance.prefab), ('main', 'shelf'));
    // What it holds is not put back on the screen beside it.
    expect(config().layout.removed, {'system:app/a'});

    // In the list it is marked as an instance, as the quick actions are,
    // and says of what; which prefab that is cannot be swapped from its
    // settings.
    expect(
      find.descendant(
        of: find.byType(ObjectTree),
        matching: find.byIcon(prefabIcon),
      ),
      findsNWidgets(2),
    );
    expect(find.byTooltip('Prefab: Shelf'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InstanceSettings),
        matching: find.text('Shelf'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(InstanceSettings),
        matching: find.byType(ChoiceBox<String>),
      ),
      findsNothing,
    );

    // Its instance shows the prefab and can open it.
    expect(find.byTooltip('Rename'), findsNothing);
    await press(tester, find.widgetWithText(OutlinedButton, 'Open'));
    expect(ref.read(prefabModeProvider)?.id, 'shelf');
    expect(find.text('1 instance'), findsOneWidget);

    await press(tester, find.text('Delete'));
    expect(find.textContaining('1 instance will be unpacked'), findsOneWidget);
    await press(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(ref.read(prefabModeProvider), isNull);
    expect(config().prefabs, isEmpty);
    final back = config().layout.pane('main')!;
    expect(back.children.single.handed, ['system:app/a']);
    expect(config().layout.removed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a prefab opened from inside another is on the trail back', (
    tester,
  ) async {
    final ref = await pump(
      tester,
      config: LauncherConfig(
        layout: homeLayout(['system:app/a']),
        prefabs: [
          Prefab(
            id: 'inner',
            name: 'Inner',
            root: Node.pane(
              id: 'root',
              mode: PaneMode.column,
              vars: const {'source': Variable(null, type: VarType.entity)},
              children: [
                drawn(
                  'label',
                  textModule.name,
                  values: const {'text': '{{source.label}}'},
                ),
              ],
            ),
          ),
          Prefab(
            id: 'outer',
            name: 'Outer',
            root: Node.pane(
              id: 'root',
              mode: PaneMode.column,
              vars: const {'source': Variable(null, type: VarType.entity)},
              children: const [
                // Hands on what it was handed.
                Node(
                  id: 'in',
                  prefab: 'inner',
                  modules: {
                    'variables': {
                      'source': {'value': '{{source.id}}', 'type': 'entity'},
                    },
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Finder crumb(String name) => find.descendant(
      of: find.byType(PrefabBar),
      matching: find.widgetWithText(TextButton, name),
    );
    openPrefab(ref, 'outer');
    await tester.pumpAndSettle();
    expect(onStage('Alpha'), findsOneWidget);
    await press(tester, find.text('Objects'));
    await press(tester, inTree('in'));
    await press(tester, find.widgetWithText(OutlinedButton, 'Open'));
    expect(ref.read(prefabTrailProvider).map((step) => step.id), [
      'outer',
      'inner',
    ]);
    // Drawn with what the one around it was drawn with.
    expect(onStage('Alpha'), findsOneWidget);
    expect(inTree('label'), findsOneWidget);
    expect(crumb('Home screen'), findsOneWidget);
    expect(crumb('Outer'), findsOneWidget);
    expect(find.byTooltip('Back to Outer'), findsOneWidget);

    // Back a step, to the instance it was opened from.
    await press(tester, crumb('Outer'));
    expect(ref.read(prefabModeProvider)?.id, 'outer');
    expect(ref.read(selectionProvider), {'in'});
    expect(onStage('Alpha'), findsOneWidget);
    expect(crumb('Outer'), findsNothing);

    // The arrow goes one step; Home screen goes all the way.
    await press(tester, find.widgetWithText(OutlinedButton, 'Open'));
    await press(tester, find.byTooltip('Back to Outer'));
    expect(ref.read(prefabModeProvider)?.id, 'outer');
    await press(tester, find.widgetWithText(OutlinedButton, 'Open'));
    await press(tester, crumb('Home screen'));
    expect(ref.read(prefabTrailProvider), isEmpty);
    expect(find.byType(TvScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an instance has a field for each exposed variable', (
    tester,
  ) async {
    var own = const <String, Variable>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [entitiesProvider.overrideWith((ref) async => const [])],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => InstanceVariables(
                declared: const {
                  'size': Variable(3, type: VarType.number),
                  'secret': Variable(1, exposed: false),
                  'worked': Variable(null, when: '{{size}}'),
                },
                own: own,
                onChanged: (next) => setState(() => own = next),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('size'), findsOneWidget);
    expect(find.text('secret'), findsNothing);
    expect(find.text('worked'), findsNothing);
    expect(find.byTooltip('Revert to prefab'), findsNothing);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // Stored with the prefab's type; put back, it is not stored at all.
    expect((own['size']!.value, own['size']!.type), (4, VarType.number));
    await tester.tap(find.byTooltip('Revert to prefab'));
    await tester.pumpAndSettle();
    expect(own, isEmpty);
  });
}
