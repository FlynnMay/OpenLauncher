import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/pane_settings.dart';

void main() {
  testWidgets("the launcher's prefabs have their rule; others are added", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final own = builtInPrefabs.first.copyWith(
      id: 'big-entity',
      name: 'Big entity',
    );
    var pane = Component.pane(id: 'p');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => PaneSettings(
                title: 'Pane',
                prefabs: {
                  for (final prefab in [...builtInPrefabs, own])
                    prefab.id: prefab,
                },
                panes: [pane],
                onChanged: (how) => setState(() => pane = how(pane)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Prefab rules'));
    await tester.pumpAndSettle();
    // There without being added, and saying nothing yet.
    expect(find.text('App card'), findsOneWidget);
    expect(find.text('Folder card'), findsOneWidget);
    expect(find.text('Big entity'), findsNothing);
    expect(pane.prefabRules, isEmpty);

    await tester.tap(find.text('Add a rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Big entity').last);
    await tester.pumpAndSettle();
    expect(pane.prefabRules, {
      'big-entity': {'variant': 'stacked'},
    });
    expect(find.text('Add a rule'), findsNothing);

    await tester.tap(find.text('Take the rule for Big entity away'));
    await tester.pumpAndSettle();
    expect(pane.prefabRules, isEmpty);
    expect(find.text('Add a rule'), findsOneWidget);
    // The launcher's own cannot be taken away, only left to each entity.
    expect(find.textContaining('Take the rule for App card'), findsNothing);
  });
}
