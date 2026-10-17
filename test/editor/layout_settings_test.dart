import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  testWidgets("the launcher's prefabs have their rule; others are added", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final own = systemPrefabs.first.copyWith(
      id: 'big-entity',
      name: 'Big entity',
    );
    var container = Node.layout(id: 'p');
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
                builder: (context, setState) => LayoutSettings(
                  title: 'Layout',
                  prefabs: {
                    for (final prefab in [...systemPrefabs, own])
                      prefab.id: prefab,
                  },
                  containers: [container],
                  onChanged: (how) =>
                      setState(() => container = how(container)),
                ),
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
    expect(container.prefabRules, isEmpty);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Big entity').last);
    await tester.pumpAndSettle();
    expect(container.prefabRules, {
      'big-entity': {'variant': 'stacked'},
    });
    expect(find.text('Add rule'), findsNothing);

    await tester.tap(find.text('Remove rule for Big entity'));
    await tester.pumpAndSettle();
    expect(container.prefabRules, isEmpty);
    expect(find.text('Add rule'), findsOneWidget);
    // The launcher's own cannot be taken away, only left to each entity.
    expect(find.textContaining('Remove rule for App card'), findsNothing);
  });

  testWidgets('scrolling each way is a tick box', (tester) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var container = Node.layout(id: 'p');
    var changes = 0;
    late StateSetter redraw;
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
                builder: (context, setState) {
                  redraw = setState;
                  return LayoutSettings(
                    title: 'Layout',
                    containers: [container],
                    onChanged: (how) => setState(() {
                      changes++;
                      container = how(container);
                    }),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    bool? ticked(String label) => tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label))
        .value;
    // A new container on cells scrolls down.
    expect(
      (ticked('Horizontal scroll'), ticked('Vertical scroll')),
      (false, true),
    );

    await tester.tap(find.text('Horizontal scroll'));
    await tester.pump();
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect((container.scrollsAcross, container.scrollsDown), (true, false));
    expect(container.scroll, containsPair('down', false));
    expect(changes, 2);
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect(container.scroll, containsPair('down', true));

    // A scroll bar is chosen, then its look has a section of its own.
    expect(find.text('Thickness'), findsNothing);
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progress').last);
    await tester.pumpAndSettle();
    expect(container.scrollbar, 'progress');
    expect(find.text('Show scroll bar'), findsOneWidget);
    for (final prop in stylePropsOf(scrollbarStyle)) {
      expect(find.text(prop.label), findsOneWidget, reason: prop.key);
    }
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(NumberField, 'Thickness'),
        matching: find.byTooltip('Increase'),
      ),
    );
    await tester.pump();
    expect(container.scroll, containsPair('scrollbarSize', 7));
    // One that scrolls neither way has none to show.
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect(container.scrollsDown, isFalse);
    await tester.tap(find.text('Horizontal scroll'));
    await tester.pump();
    expect(container.scrollbar, isNull);
    expect(find.text('Scroll bar'), findsNothing);
    expect(find.text('Thickness'), findsNothing);
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect(container.scrollbar, 'progress');

    // A row or a column does not scroll until ticked, and only along
    // itself.
    redraw(() => container = Node.layout(id: 'p', mode: LayoutMode.row));
    await tester.pump();
    expect(
      (ticked('Horizontal scroll'), ticked('Vertical scroll')),
      (false, false),
    );

    redraw(() => container = Node.layout(id: 'p', mode: LayoutMode.column));
    await tester.pump();
    changes = 0;
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect((container.scroll['down'], container.scrollsDown), (true, true));
    expect(changes, 1);
    await tester.tap(find.text('Horizontal scroll'));
    await tester.pump();
    expect(container.scrollsAcross, isFalse);
  });
}
