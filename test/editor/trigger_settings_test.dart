import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  late Triggers on;

  Future<void> show(
    WidgetTester tester, {
    Triggers set = const {},
    Triggers defaults = const {},
    Variables scope = const {},
  }) async {
    tester.view.physicalSize = const Size(300, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    on = set;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform([
              InstalledApp(packageName: 'a', label: 'Alpha', isBanner: true),
            ], []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => TriggerSettings(
                  set: on,
                  defaults: defaults,
                  scope: scope,
                  onChanged: (next) => setState(() => on = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Finder box, String label) async {
    await tester.tap(box);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a trigger is added, then an entity, then one of its actions', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('No triggers'), findsOneWidget);
    await choose(tester, find.text('Add trigger'), 'On press');
    // Nothing is saved until an entity is chosen.
    expect(on, isEmpty);
    expect(find.text('On press'), findsOneWidget);

    await tester.tap(find.byType(SearchBox));
    await tester.pumpAndSettle();
    // Only what has actions is offered.
    expect(find.text('Clock'), findsNothing);
    expect(find.text('Alpha'), findsWidgets);
    await tester.tap(find.text('Media Player').last);
    await tester.pumpAndSettle();
    expect(on, {
      Trigger.press: [
        const Act('playPause', {'entity': 'system:media'}),
      ],
    });

    // The entity's own actions, and no other's.
    await tester.tap(find.text('Play or pause'));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Set a variable'), findsNothing);
    await tester.tap(find.text('Next').last);
    await tester.pumpAndSettle();
    expect(on[Trigger.press], [
      const Act('next', {'entity': 'system:media'}),
    ]);

    // Aimed at another entity, it takes that one's first action.
    await choose(tester, find.byType(SearchBox), 'Updates');
    expect(on[Trigger.press], [
      const Act('check', {'entity': 'system:updates'}),
    ]);

    await tester.tap(find.byTooltip('Remove action'));
    await tester.pumpAndSettle();
    expect(on, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a prefab's chain shows as its own until changed", (
    tester,
  ) async {
    const open = Act('open', {'entity': sourceEntity});
    await show(
      tester,
      defaults: const {
        Trigger.press: [open],
      },
      scope: const {'source': Variable('system:app/a', type: VarType.entity)},
    );
    expect(find.text('From prefab'), findsOneWidget);
    // The variable is the target, read as the entity it holds.
    expect(find.text('source (Alpha)'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    // Only that app's actions are offered.
    await choose(tester, find.text('Open'), 'App info');
    expect(on, {
      Trigger.press: [
        const Act('info', {'entity': sourceEntity}),
      ],
    });
    expect(find.text('From prefab'), findsNothing);

    await tester.tap(find.byTooltip('Reset to prefab'));
    await tester.pumpAndSettle();
    expect(on, isEmpty);

    // Removed, the prefab's is switched off, not forgotten.
    await tester.tap(find.byTooltip('Remove trigger'));
    await tester.pumpAndSettle();
    expect(on, {Trigger.press: <Act>[]});
    expect(find.text('Prefab actions disabled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a variable is set by a control of its type', (tester) async {
    tester.view.physicalSize = const Size(300, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Variables variables = const {
      'count': Variable(3, type: VarType.number),
      'on': Variable(null, type: VarType.bool),
      'title': Variable('Hi {{system:clock.time}}', type: VarType.text),
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform(const [], const []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => VariablesSettings(
                  variables: variables,
                  onChanged: (next) => setState(() => variables = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A number has a box with a step either side, and may have a fraction.
    await tester.tap(find.byTooltip('Increase'));
    await tester.pumpAndSettle();
    expect(variables['count']!.value, 4);
    await tester.enterText(find.widgetWithText(TextField, '4'), '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(variables['count']!.value, 0.5);
    expect(variables['count']!.type, VarType.number);

    // A yes or no is a tick.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Value'));
    await tester.pumpAndSettle();
    expect(variables['on']!.value, true);

    // Text stays as written, templates and all.
    expect(variables['title']!.value, 'Hi {{system:clock.time}}');

    // As an expression, the number is written as a template instead.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Expression').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Increase'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, '0.5'),
      '{{system:clock.second}}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(variables['count']!.value, '{{system:clock.second}}');
    expect(variables.keys, ['count', 'on', 'title']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an area of the launcher or the TV, then what is there', (
    tester,
  ) async {
    await show(
      tester,
      set: const {
        Trigger.press: [Act('os://nothing/here')],
      },
    );
    expect(
      find.text('There is nothing at "os://nothing/here".'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Remove action'));
    await tester.pumpAndSettle();
    expect(on, isEmpty);

    await choose(tester, find.text('Add trigger'), 'On press');
    await tester.tap(find.byType(SearchBox));
    await tester.pumpAndSettle();
    expect(find.text('Launcher'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBox),
        matching: find.byType(TextField),
      ),
      'layers',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('launcher://layers').last);
    await tester.pumpAndSettle();
    // The area's first operation, then any of the others there.
    expect(on[Trigger.press], [const Act('launcher://layers/new')]);
    await choose(
      tester,
      find.text('Create a new layer'),
      'Move a component to the top layer',
    );
    expect(on[Trigger.press], [const Act('launcher://layers/raise')]);
    expect(find.text('of (component ID)'), findsOneWidget);

    // Aimed at an entity, it is that entity's action again.
    await tester.tap(find.byType(SearchBox));
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBox),
        matching: find.byType(TextField),
      ),
      'Media',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media Player').last);
    await tester.pumpAndSettle();
    expect(on[Trigger.press], [
      const Act('playPause', {'entity': 'system:media'}),
    ]);
    expect(tester.takeException(), isNull);
  });
}
