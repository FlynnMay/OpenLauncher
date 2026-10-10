import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/gradient_bar.dart';

void main() {
  const black = 0xFF000000, white = 0xFFFFFFFF, red = 0xFFFF0000;
  // The bar itself is 200 wide, starting at x = 0 + the inset.
  const left = GradientBar.inset, width = 200.0;

  Future<List<List<ColourStop>>> show(
    WidgetTester tester,
    List<ColourStop> stops, {
    int max = 8,
  }) async {
    final changes = <List<ColourStop>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width + GradientBar.inset * 2,
              child: GradientBar(
                stops: stops,
                max: max,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('a handle is dragged to where its colour shifts', (tester) async {
    final changes = await show(tester, const [
      (colour: black, at: 0),
      (colour: red, at: 0.5),
      (colour: white, at: 1),
    ]);
    // The middle handle, just under the bar.
    final gesture = await tester.startGesture(const Offset(left + 100, 32));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(30, 0));
    // Nothing is changed until it is let go.
    expect(changes, isEmpty);
    await gesture.up();
    expect(changes, hasLength(1));
    expect(changes.single.map((stop) => stop.colour), [black, red, white]);
    expect(changes.single[1].at, closeTo(0.8, 0.03));
  });

  testWidgets('a handle stays between its neighbours', (tester) async {
    final changes = await show(tester, const [
      (colour: black, at: 0),
      (colour: red, at: 0.5),
      (colour: white, at: 0.7),
    ]);
    await tester.dragFrom(const Offset(left + 100, 32), const Offset(180, 0));
    expect(changes.single[1].at, 0.7);
  });

  testWidgets('pressing the bar adds the colour it has there', (tester) async {
    final changes = await show(tester, const [
      (colour: black, at: 0),
      (colour: white, at: 1),
    ]);
    await tester.tapAt(const Offset(left + 50, 10));
    expect(changes.single, hasLength(3));
    expect(changes.single[1].at, 0.25);
    final grey = Color(changes.single[1].colour);
    expect(grey.r, closeTo(0.25, 0.01));
    expect(grey.a, 1);
  });

  testWidgets('takes no more colours than it is allowed', (tester) async {
    final changes = await show(tester, const [
      (colour: black, at: 0),
      (colour: white, at: 1),
    ], max: 2);
    await tester.tapAt(const Offset(left + 50, 10));
    expect(changes, isEmpty);
  });

  testWidgets('the picked colour is moved a percent at a time', (tester) async {
    final changes = await show(tester, const [
      (colour: black, at: 0),
      (colour: red, at: 0.5),
      (colour: white, at: 1),
    ]);
    await tester.tapAt(const Offset(left + 100, 32));
    await tester.pump();
    expect(find.text('Colour 2'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    expect(changes.single[1].at, 0.51);
  });
}
