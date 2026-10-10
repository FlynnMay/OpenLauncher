import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/tree_view.dart';

void main() {
  const nodes = [
    TreeNode<String>(
      label: 'Fruit',
      children: [
        TreeNode(label: 'Apple', value: 'apple'),
        TreeNode(label: 'Pear', value: 'pear'),
      ],
    ),
    TreeNode<String>(label: 'Bread', value: 'bread'),
  ];

  Future<Set<String>> pump(WidgetTester tester, Set<String> checked) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => TreeView<String>(
              nodes: nodes,
              checked: checked,
              onChanged: (values, on) => setState(
                () => on ? checked.addAll(values) : checked.removeAll(values),
              ),
            ),
          ),
        ),
      ),
    );
    return checked;
  }

  bool? ticked(WidgetTester tester, String label) => tester
      .widget<Checkbox>(
        find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
          matching: find.byType(Checkbox),
        ),
      )
      .value;

  testWidgets('a heading ticks and unticks everything under it', (
    tester,
  ) async {
    final checked = await pump(tester, {});
    await tester.tap(find.text('Fruit'));
    await tester.pump();
    expect(checked, {'apple', 'pear'});
    expect(ticked(tester, 'Fruit'), isTrue);

    await tester.tap(find.text('Fruit'));
    await tester.pump();
    expect(checked, isEmpty);
  });

  testWidgets('a heading with some ticked is neither, and one press fills it', (
    tester,
  ) async {
    final checked = await pump(tester, {});
    await tester.tap(find.text('Pear'));
    await tester.pump();
    expect(checked, {'pear'});
    expect(ticked(tester, 'Fruit'), isNull);
    expect(ticked(tester, 'Bread'), isFalse);

    await tester.tap(find.text('Fruit'));
    await tester.pump();
    expect(checked, {'apple', 'pear'});
  });

  testWidgets('a heading closes and opens without changing what is ticked', (
    tester,
  ) async {
    final checked = await pump(tester, {'apple'});
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('Apple'), findsNothing);
    expect(find.text('Bread'), findsOneWidget);
    expect(checked, {'apple'});

    await tester.tap(find.byTooltip('Open'));
    await tester.pump();
    expect(find.text('Apple'), findsOneWidget);
  });

  testWidgets('picking: a press picks one line, a bare heading only opens', (
    tester,
  ) async {
    final pressed = <String>[];
    // Made anew each time, as a tree of what is on the screen is.
    List<TreeNode<String>> made() => [
      TreeNode(
        id: 'fruit',
        label: 'Fruit',
        children: const [TreeNode(label: 'Apple', value: 'apple')],
      ),
      TreeNode(
        id: 'box',
        label: 'Box',
        value: 'box',
        children: const [TreeNode(label: 'Pear', value: 'pear')],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => TreeView<String>.pick(
              nodes: made(),
              picked: {...pressed},
              onPicked: (value) => setState(() => pressed.add(value)),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('Box'));
    await tester.pump();
    expect(pressed, ['box']);
    expect(find.text('Pear'), findsOneWidget);

    await tester.tap(find.text('Fruit'));
    await tester.pump();
    expect(pressed, ['box']);
    expect(find.text('Apple'), findsNothing);
    // Still closed though the lines are new ones.
    await tester.tap(find.text('Pear'));
    await tester.pump();
    expect(pressed, ['box', 'pear']);
    expect(find.text('Apple'), findsNothing);
  });
}
