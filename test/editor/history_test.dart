import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/panels/panels.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher_domain/commands/commands.dart';

import '../support/fake_tv.dart';
import '../support/packs.dart';

const _entities = [
  Entity(id: 'system:app/a', category: appCategory, label: 'Alpha'),
  Entity(id: 'system:app/b', category: appCategory, label: 'Beta'),
];

TvState _state() => TvState(
  entities: _entities,
  config: LauncherConfig(layout: homeLayout(['system:app/a', 'system:app/b'])),
  visuals: const [],
);

void main() {
  group('history', () {
    late FakeTv tv;
    late ProviderContainer container;

    setUp(() async {
      tv = FakeTv(_state());
      container = ProviderContainer(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => tv.pushed.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(configProvider, (_, _) {});
      await container.read(configProvider.future);
    });

    LauncherConfig config() => container.read(configProvider).value!;
    ConfigController controller() => container.read(configProvider.notifier);
    History history() => container.read(historyProvider.notifier);
    Moments moments() => container.read(historyProvider);
    bool placed(String id) =>
        config().layout.items.any((item) => item.handed.contains(id));

    test('a change is undone and redone, with what was selected', () async {
      final card = config().layout.items
          .firstWhere((item) => item.handed.contains('system:app/a'))
          .id;
      container.read(selectionProvider.notifier).tap(card, adding: false);
      await controller().setLayout(config().layout.without({'system:app/a'}));
      container.read(selectionProvider.notifier).clear();
      expect(placed('system:app/a'), isFalse);
      expect(moments().past, hasLength(1));

      await history().undo();
      await pumpEventQueue();
      expect(placed('system:app/a'), isTrue);
      expect(container.read(selectionProvider), {card});
      expect(moments().past, isEmpty);
      expect(moments().future, hasLength(1));
      // The TV does each step.
      expect(tv.sent, ['layout', 'undo']);

      await history().redo();
      await pumpEventQueue();
      expect(placed('system:app/a'), isFalse);
      expect(container.read(selectionProvider), isEmpty);
      expect(moments().past, hasLength(1));
      expect(moments().future, isEmpty);

      // With nothing left to redo, nothing happens.
      await history().redo();
      expect(tv.sent, hasLength(3));
    });

    test('a new change drops what could be redone', () async {
      await controller().setLayout(config().layout.without({'system:app/a'}));
      await history().undo();
      await controller().setLayout(config().layout.without({'system:app/b'}));
      expect(moments().future, isEmpty);
      await history().undo();
      await pumpEventQueue();
      expect(placed('system:app/a') && placed('system:app/b'), isTrue);
    });

    test('a save that changes nothing is not a step', () async {
      await controller().setLayout(config().layout);
      expect(moments().past, isEmpty);
      expect(tv.sent, isEmpty);
    });

    test('names, pictures and wallpapers are steps like any other', () async {
      await controller().setName('system:app/a', 'Films');
      await controller().setWallpapers(['http://tv/api/media/w-1.png']);
      await controller().setIconOverride(
        'system:app/a',
        'http://tv/api/media/p.png',
      );
      expect(moments().past, hasLength(3));

      // Undoing past an upload only stops pointing at its file.
      await history().undo();
      await pumpEventQueue();
      expect(config().iconOverrides, isEmpty);
      expect(config().wallpapers, hasLength(1));
      await history().undo();
      await history().undo();
      await pumpEventQueue();
      expect(config().wallpapers, isEmpty);
      expect(config().names, isEmpty);
      expect(tv.sent, [
        'config names',
        'config wallpapers',
        'config iconOverrides',
        'undo',
        'undo',
        'undo',
      ]);
    });

    test('a layout and a setting changed together are one step', () async {
      await controller().change(
        (c) => c.copyWith(
          layout: c.layout.without({'system:app/a'}),
          names: {'system:app/b': 'Series'},
        ),
      );
      expect(tv.sent, ['layout + config names']);
      expect(moments().past, hasLength(1));

      await history().undo();
      await pumpEventQueue();
      expect(placed('system:app/a'), isTrue);
      expect(config().names, isEmpty);
    });

    test('the open prefab is part of the step', () async {
      await controller().setName('system:app/a', 'Films');
      container.read(prefabTrailProvider.notifier).open('system:app-card');
      await history().undo();
      expect(container.read(prefabTrailProvider), isEmpty);
      await history().redo();
      expect(container.read(prefabTrailProvider).single.id, 'system:app-card');
    });

    test('only the newest steps are kept', () async {
      for (var i = 0; i <= History.limit; i++) {
        await controller().setWallpaperEvery(i + 1);
      }
      expect(moments().past, hasLength(History.limit));
    });

    test('a TV with nothing to undo starts the history again', () async {
      await controller().setLayout(config().layout.without({'system:app/a'}));
      tv.restart();
      await expectLater(history().undo(), throwsA(isA<CommandRefused>()));
      expect(moments().past, isEmpty);
      expect(moments().future, isEmpty);
    });
  });

  Future<WidgetRef> pump(WidgetTester tester, FakeTv tv, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => tv.pushed.stream),
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

  testWidgets('a command the TV refuses is said, and is not a step to undo', (
    tester,
  ) async {
    final tv = FakeTv(_state())..commandRefusal = 'That layout is gone.';
    final ref = await pump(tester, tv, const Size(1600, 900));
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ObjectTree),
        matching: find.text('Alpha'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    // Settling would wait for the message to go again.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('That layout is gone.'), findsOneWidget);
    expect(ref.read(historyProvider).past, isEmpty);
    expect(
      ref
          .read(configProvider)
          .value!
          .layout
          .items
          .any((item) => item.handed.contains('system:app/a')),
      isTrue,
    );
  });

  testWidgets('Ctrl+Z brings back what Delete removed, selected again', (
    tester,
  ) async {
    final ref = await pump(tester, FakeTv(_state()), const Size(1600, 900));
    bool placed() => ref
        .read(configProvider)
        .value!
        .layout
        .items
        .any((item) => item.handed.contains('system:app/a'));
    IconButton button(String tooltip) => tester.widget(
      find.widgetWithIcon(IconButton, switch (tooltip) {
        'undo' => Icons.undo,
        _ => Icons.redo,
      }),
    );
    expect(button('undo').onPressed, isNull);
    expect(button('redo').onPressed, isNull);

    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ObjectTree),
        matching: find.text('Alpha'),
      ),
    );
    await tester.pumpAndSettle();
    final picked = ref.read(selectionProvider);
    expect(picked, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(placed(), isFalse);
    expect(ref.read(selectionProvider), isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(placed(), isTrue);
    expect(ref.read(selectionProvider), picked);
    expect(button('redo').onPressed, isNotNull);

    // The button does what Ctrl+Shift+Z and Ctrl+Y do.
    await tester.tap(find.byIcon(Icons.redo));
    await tester.pumpAndSettle();
    expect(placed(), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(placed(), isFalse);
  });
}
