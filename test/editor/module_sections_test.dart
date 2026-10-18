import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/modules.dart';
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
                builder: (context, setState) => PrefabRulesSettings(
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
                  return ModuleSections(
                    nodes: [container],
                    parents: const [],
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
    expect(find.text('Scroll bar look'), findsNothing);
    expect(find.text('Thickness'), findsNothing);
    await tester.tap(find.text('Vertical scroll'));
    await tester.pump();
    expect(container.scrollbar, 'progress');

    // A row or a column does not scroll until ticked, and only along
    // itself.
    redraw(
      () => container = Node.layout(
        id: 'p',
        mode: LayoutMode.row,
        scroll: const {},
      ),
    );
    await tester.pump();
    expect(
      (ticked('Horizontal scroll'), ticked('Vertical scroll')),
      (false, false),
    );

    redraw(
      () => container = Node.layout(
        id: 'p',
        mode: LayoutMode.column,
        scroll: const {},
      ),
    );
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

  group('adding and removing modules', () {
    test('a module brings what it needs, and keeps it', () {
      const text = Node(
        id: 't',
        modules: {
          'text': {'text': 'Hi'},
        },
      );
      final scrolled = withAdded(text, scrollModule);
      expect(scrolled.modules.keys, ['text', 'layout', 'scroll']);
      expect(needing(scrolled, layoutModule), ['Scroll']);
      expect(needing(scrolled, textModule), isEmpty);
    });

    test('without its Layout, children keep their places in it', () {
      final grid = Node.layout(
        id: 'g',
        columns: 4,
        children: [
          Node.layout(id: 'a', w: 2),
          Node.layout(id: 'b', w: 2, h: 2),
        ],
      );
      final free = withRemoved(grid, layoutModule);
      expect(free.mode, LayoutMode.free);
      expect(free.children.map((child) => child.transform.toJson()), [
        {
          'anchors': [0, 0, 0.5, 0.5],
        },
        {
          'anchors': [0.5, 0, 1, 1],
        },
      ]);
      expect(free.children.every((child) => !child.added('sizing')), isTrue);

      final row = withRemoved(
        Node.layout(
          id: 'r',
          mode: LayoutMode.row,
          children: [
            Node.layout(id: 'a'),
            Node.layout(id: 'b'),
          ],
        ),
        layoutModule,
      );
      expect(row.children.map((child) => child.transform.toJson()), [
        {
          'anchors': [0, 0, 0.5, 1],
        },
        {
          'anchors': [0.5, 0, 1, 1],
        },
      ]);
    });

    test('an instance stores only what differs from its prefab', () {
      final prefabs = {for (final prefab in systemPrefabs) prefab.id: prefab};
      const button = Node(id: 'b', prefab: 'system:button');
      expect(resolved(button, prefabs).focusScale, 1.03);

      // The default where the prefab has another is written out.
      final grown = withInstanceValue(
        button,
        focusModule,
        'scale',
        null,
        prefabs,
      );
      expect(grown.modules['focus'], {'scale': FocusModule.defaultScale});
      // The prefab's own value takes nothing, and the module goes with it.
      final back = withInstanceValue(grown, focusModule, 'scale', 103, prefabs);
      expect(back.modules, isEmpty);
      expect(
        withInherited(grown, focusModule, 'scale', prefabs).modules,
        isEmpty,
      );

      final off = withSwitch(button, focusModule, false, prefabs);
      expect(off.modules['focus'], {enabledKey: false});
      expect(withSwitch(off, focusModule, true, prefabs).modules, isEmpty);
    });
  });

  testWidgets('a module is added from a search, switched off and removed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var node = const Node(
      id: 't',
      modules: {
        'text': {'text': 'Hi'},
      },
    );
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
                builder: (context, setState) => ModuleSections(
                  nodes: [node],
                  parents: const [],
                  onChanged: (how) => setState(() => node = how(node)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A node shows only what it has.
    expect(find.widgetWithText(SectionHeader, 'Text'), findsOneWidget);
    expect(find.widgetWithText(SectionHeader, 'Style'), findsNothing);

    await tester.tap(find.byType(SearchBox));
    await tester.pumpAndSettle();
    // It draws text already, so nothing else that draws is offered.
    expect(find.text('Picture'), findsNothing);
    expect(find.text('Slot'), findsNothing, reason: 'only in a prefab');
    await tester.ensureVisible(find.text('Focus').last);
    await tester.tap(find.text('Focus').last);
    await tester.pumpAndSettle();
    expect(node.focusable, isTrue);
    expect(find.text('Focused size %'), findsOneWidget);

    // Off, it stays with its values, and does nothing.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SectionHeader, 'Focus'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    expect((node.added('focus'), node.focusable), (true, false));
    expect(find.text('Focused size %'), findsOneWidget);
    expect(find.textContaining('Switched off'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SectionHeader, 'Focus'),
        matching: find.byTooltip('Module menu'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove module'));
    await tester.pumpAndSettle();
    expect(node.added('focus'), isFalse);
    expect(find.widgetWithText(SectionHeader, 'Focus'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("an instance switches off its prefab's module, not removes it", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var node = const Node(id: 'b', prefab: 'system:button');
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
                builder: (context, setState) => ModuleSections(
                  nodes: [node],
                  parents: const [],
                  onChanged: (how) => setState(() => node = how(node)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final focus = find.widgetWithText(SectionHeader, 'Focus');
    await tester.tap(
      find.descendant(of: focus, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(node.modules, {
      'focus': {enabledKey: false},
    });
    await tester.tap(
      find.descendant(of: focus, matching: find.byTooltip('Module menu')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove (its prefab gives it)'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<VoidCallback>>(
            find.ancestor(
              of: find.text('Remove (its prefab gives it)'),
              matching: find.byType(PopupMenuItem<VoidCallback>),
            ),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('every node has Visibility: it cannot be added or removed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var node = Node.layout(id: 'p');
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
                builder: (context, setState) => ModuleSections(
                  nodes: [node],
                  parents: const [],
                  onChanged: (how) => setState(() => node = how(node)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final section = find.widgetWithText(SectionHeader, 'Visibility');
    expect(section, findsOneWidget);
    expect(
      find.descendant(of: section, matching: find.byType(Checkbox)),
      findsNothing,
    );
    expect(
      find.descendant(of: section, matching: find.byTooltip('Module menu')),
      findsNothing,
    );
    // Saying nothing is not saved.
    expect(node.modules, isNot(contains('visibility')));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Visible'));
    await tester.pumpAndSettle();
    expect(node.hidden, isTrue);
    expect(
      node.toJson()['modules'],
      containsPair('visibility', {'visible': false}),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Visible'));
    await tester.pumpAndSettle();
    expect(node.hidden, isFalse);
    expect(node.toJson()['modules'], isNot(contains('visibility')));
  });
}
