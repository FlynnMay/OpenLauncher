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

class _Tv extends TvApi {
  final sent = <String>[];

  /// When set, the TV refuses what it is sent.
  bool refuses = false;

  @override
  Future<void> setLayout(Layout layout) async {
    if (refuses) throw Exception('No');
    sent.add('layout');
  }

  @override
  Future<void> setConfig(Map<String, Object?> changed) async =>
      sent.add('config ${changed.keys.join(' ')}');
}

const _entities = [
  Entity(id: 'app:a', category: appCategory, label: 'Alpha'),
  Entity(id: 'app:b', category: appCategory, label: 'Beta'),
];

TvState _state() => TvState(
  entities: _entities,
  config: LauncherConfig(layout: Layout.initial(['app:a', 'app:b'])),
  components: const [],
);

void main() {
  group('history', () {
    late _Tv tv;
    late ProviderContainer container;

    setUp(() async {
      tv = _Tv();
      container = ProviderContainer(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
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
          .firstWhere((item) => item.handed.contains('app:a'))
          .id;
      container.read(selectionProvider.notifier).tap(card, adding: false);
      await controller().setLayout(config().layout.without({'app:a'}));
      container.read(selectionProvider.notifier).clear();
      expect(placed('app:a'), isFalse);
      expect(moments().past, hasLength(1));

      await history().undo();
      expect(placed('app:a'), isTrue);
      expect(container.read(selectionProvider), {card});
      expect(moments().past, isEmpty);
      expect(moments().future, hasLength(1));
      // The TV is sent each step.
      expect(tv.sent, ['layout', 'layout']);

      await history().redo();
      expect(placed('app:a'), isFalse);
      expect(container.read(selectionProvider), isEmpty);
      expect(moments().past, hasLength(1));
      expect(moments().future, isEmpty);

      // With nothing left to redo, nothing happens.
      await history().redo();
      expect(tv.sent, hasLength(3));
    });

    test('a new change drops what could be redone', () async {
      await controller().setLayout(config().layout.without({'app:a'}));
      await history().undo();
      await controller().setLayout(config().layout.without({'app:b'}));
      expect(moments().future, isEmpty);
      await history().undo();
      expect(placed('app:a') && placed('app:b'), isTrue);
    });

    test('a save that changes nothing is not a step', () async {
      await controller().setLayout(config().layout);
      expect(moments().past, isEmpty);
      expect(tv.sent, isEmpty);
    });

    test('names, pictures and wallpapers are steps like any other', () async {
      await controller().setName('app:a', 'Films');
      await controller().setWallpapers(['http://tv/api/media/w-1.png']);
      await controller().setIconOverride('app:a', 'http://tv/api/media/p.png');
      expect(moments().past, hasLength(3));

      // Undoing past an upload only stops pointing at its file.
      await history().undo();
      expect(config().iconOverrides, isEmpty);
      expect(config().wallpapers, hasLength(1));
      await history().undo();
      await history().undo();
      expect(config().wallpapers, isEmpty);
      expect(config().names, isEmpty);
      expect(tv.sent, [
        'config names',
        'config wallpapers',
        'config iconOverrides',
        'config iconOverrides',
        'config wallpapers',
        'config names',
      ]);
    });

    test('the open prefab is part of the step', () async {
      await controller().setName('app:a', 'Films');
      container.read(prefabTrailProvider.notifier).open('app-card');
      await history().undo();
      expect(container.read(prefabTrailProvider), isEmpty);
      await history().redo();
      expect(container.read(prefabTrailProvider).single.id, 'app-card');
    });

    test('only the newest steps are kept', () async {
      for (var i = 0; i <= History.limit; i++) {
        await controller().setWallpaperEvery(i + 1);
      }
      expect(moments().past, hasLength(History.limit));
      expect(moments().past.first.config.wallpaperEvery, 1);
    });

    test('a step the TV refuses starts the history again', () async {
      await controller().setLayout(config().layout.without({'app:a'}));
      tv.refuses = true;
      await expectLater(history().undo(), throwsException);
      expect(moments().past, isEmpty);
      expect(moments().future, isEmpty);
    });
  });

  Future<WidgetRef> pump(WidgetTester tester, _Tv tv, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith((ref) => Stream.value(_state())),
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

  testWidgets('Ctrl+Z brings back what Delete removed, selected again', (
    tester,
  ) async {
    final ref = await pump(tester, _Tv(), const Size(1600, 900));
    bool placed() => ref
        .read(configProvider)
        .value!
        .layout
        .items
        .any((item) => item.handed.contains('app:a'));
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
