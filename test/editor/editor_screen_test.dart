import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/object_tree.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_link.dart';
import 'package:openlauncher/editor/tv_screen.dart';

class _Tv extends TvApi {
  @override
  Future<void> setLayout(Layout layout) async {}

  @override
  Future<void> setConfig(Map<String, Object?> changed) async {}

  @override
  Future<Map<Object?, Object?>> press(
    String what, {
    String? entity,
    Map<String, Object?> more = const {},
  }) async => const {'enabled': true};
}

const _entity = Entity(
  id: 'app:a',
  kind: appKind,
  target: 'app:a',
  label: 'Alpha',
);

void main() {
  Future<WidgetRef> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(_Tv()),
          tvStateProvider.overrideWith(
            (ref) => Stream.value(
              TvState(
                entities: const [_entity],
                config: LauncherConfig(layout: Layout.initial(['app:a'])),
                widgets: const [],
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
    expect((picked.item.source ?? picked.item.ref), 'app:a');

    await tester.tap(inTree('Home screen'));
    await tester.pumpAndSettle();
    expect(ref.read(selectionProvider), isEmpty);
  });

  testWidgets('under a narrow screen the three take turns', (tester) async {
    await pump(tester, const Size(420, 900));
    await tester.tap(find.text('Objects'));
    await tester.pumpAndSettle();
    await tester.tap(inTree('Alpha'));
    await tester.pumpAndSettle();
    // Picking something out brings up its settings.
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Select several').hitTestable(), findsOneWidget);
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
    expect(freeEdges(layout()), Layout.barIds);
    expect(ref.read(barProvider), isNull);

    await drag(screen.centerLeft + const Offset(10, 0));
    expect(ref.read(barProvider), 'left');
    expect(layout().panel('left'), isNotNull);
  });
}
