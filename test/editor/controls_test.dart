import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/controls/controls.dart';

void main() {
  Widget page(Key key) => MaterialApp(
    home: Material(
      child: Column(
        children: [
          Section(key: key, 'Size', const [Text('Cells wide')]),
          const Section('Corners', open: false, [Text('Top left')]),
        ],
      ),
    ),
  );

  testWidgets('a section closes and opens, and starts as it is told to', (
    tester,
  ) async {
    await tester.pumpWidget(page(const ValueKey(1)));
    expect(find.text('Cells wide'), findsOneWidget);
    expect(find.text('Top left'), findsNothing);

    await tester.tap(find.text('Size'));
    await tester.tap(find.text('Corners'));
    await tester.pump();
    expect(find.text('Cells wide'), findsNothing);
    expect(find.text('Top left'), findsOneWidget);
  });

  testWidgets('a section made anew is as the one of its name was left', (
    tester,
  ) async {
    await tester.pumpWidget(page(const ValueKey(1)));
    await tester.tap(find.text('Size'));
    await tester.pump();
    // As when something else is picked out and its settings take over.
    await tester.pumpWidget(page(const ValueKey(2)));
    expect(find.text('Cells wide'), findsNothing);
  });

  group('a number', () {
    Future<List<num?>> show(
      WidgetTester tester, {
      double? value = 4,
      bool clearable = false,
    }) async {
      final changes = <num?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) => NumberField(
                label: 'Padding',
                value: value,
                min: 0,
                max: 80,
                step: 2,
                placeholder: clearable ? 'Default' : null,
                onChanged: (next) => setState(() {
                  changes.add(next);
                  value = next * 1.0;
                }),
                onCleared: clearable
                    ? () => setState(() {
                        changes.add(null);
                        value = null;
                      })
                    : null,
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('is typed into its box, kept within its limits', (
      tester,
    ) async {
      final changes = await show(tester);
      await tester.enterText(find.byType(TextField), '31');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes, [31]);
      await tester.enterText(find.byType(TextField), '500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes, [31, 80]);
      expect(find.text('80'), findsOneWidget);
      // What is no number is dropped.
      await tester.enterText(find.byType(TextField), 'wide');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes, [31, 80]);
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('steps by its buttons and the arrow keys', (tester) async {
      final changes = await show(tester);
      await tester.tap(find.byTooltip('Increase'));
      await tester.pump();
      await tester.tap(find.byTooltip('Decrease'));
      await tester.pump();
      expect(changes, [6, 4]);
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(changes, [6, 4, 6, 26]);
    });

    testWidgets('emptied or reset, goes back to its default', (tester) async {
      final changes = await show(tester, clearable: true);
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes, [null]);
      expect(find.text('Default'), findsOneWidget);
      expect(find.byTooltip('Reset to default'), findsNothing);
      // From unset, a step starts at the least.
      await tester.tap(find.byTooltip('Increase'));
      await tester.pump();
      await tester.tap(find.byTooltip('Reset to default'));
      await tester.pump();
      expect(changes, [null, 0, null]);
    });

    testWidgets('that has to be set cannot be emptied', (tester) async {
      final changes = await show(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes, isEmpty);
      expect(find.text('4'), findsOneWidget);
    });
  });
}
