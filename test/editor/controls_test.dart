import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/controls.dart';

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
}
