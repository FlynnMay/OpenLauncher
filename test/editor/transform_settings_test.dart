import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/settings.dart';

void main() {
  const parent = Size(960, 540);

  test('new anchors keep a node where it is', () {
    final node = Node(
      id: 'a',
      transform: NodeTransform.at(const Rect.fromLTWH(100, 50, 200, 100)),
    );
    final stretched = withAnchors(node, (0, 1), (0.5, 0.5), parent);
    expect(stretched.transform.rectIn(parent), node.transform.rectIn(parent));
    expect(stretched.transform.toJson(), {
      'anchors': [0, 0.5, 1, 0.5],
      'offsets': [100, -220, -660, -120],
    });
    // And stretch with the parent from then on.
    expect(
      stretched.transform.rectIn(const Size(1060, 540)),
      const Rect.fromLTWH(100, 50, 300, 100),
    );
  });

  testWidgets('a preset or a number places it; a Layout greys it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var node = Node(
      id: 'a',
      transform: NodeTransform.at(const Rect.fromLTWH(100, 50, 200, 100)),
    );
    String? placedBy;
    late StateSetter redraw;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                return TransformSettings(
                  node: node,
                  parentSize: () => parent,
                  placedBy: placedBy,
                  onChanged: (transform) => setState(
                    () => node = node.copyWith(transform: transform),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Pinned to the top left: a place and a size.
    expect(find.text('Width'), findsOneWidget);
    expect(find.widgetWithText(NumberField, 'Width'), findsOneWidget);

    await tester.tap(find.byTooltip('Bottom, right'));
    await tester.pump();
    expect(node.transform.toJson()['anchors'], [1, 1, 1, 1]);
    expect(
      node.transform.rectIn(parent),
      const Rect.fromLTWH(100, 50, 200, 100),
    );

    // Stretched across: an inset each side.
    await tester.tap(find.byTooltip('Top, stretch across'));
    await tester.pump();
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('Width'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '660'), '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      node.transform.rectIn(parent),
      const Rect.fromLTRB(100, 50, 940, 150),
    );

    redraw(() => placedBy = "its parent's Layout");
    await tester.pump();
    expect(find.text("Placed by its parent's Layout."), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(AnchorPresets),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });
}
