import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/controls/controls.dart';

void main() {
  CarouselImage image(String id) => CarouselImage(
    id: id,
    child: Center(child: Text('picture $id')),
  );

  Future<void> pump(WidgetTester tester, Widget carousel) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, child: carousel)),
    ),
  );

  testWidgets('with room for one it is a picture to choose and replace', (
    tester,
  ) async {
    var asked = 0;
    await pump(
      tester,
      ImageCarousel(images: const [], empty: 'Nothing', onAdd: () => asked++),
    );
    expect(find.text('Nothing'), findsOneWidget);
    await tester.tap(find.text('Add'));
    expect(asked, 1);

    final removed = <String>[];
    await pump(
      tester,
      ImageCarousel(
        images: [image('a')],
        onAdd: () => asked++,
        onRemove: removed.add,
      ),
    );
    expect(find.text('picture a'), findsOneWidget);
    // Full, but one picture can always be swapped for another.
    await tester.tap(find.text('Replace'));
    expect(asked, 2);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.byTooltip('Remove'));
    expect(removed, ['a']);
  });

  testWidgets('several are gone through, put first and removed one by one', (
    tester,
  ) async {
    final first = <String>[], removed = <String>[];
    await pump(
      tester,
      ImageCarousel(
        max: 3,
        images: [image('a'), image('b'), image('c')],
        onAdd: () {},
        onRemove: removed.add,
        onFirst: first.add,
      ),
    );
    expect(find.text('1 of 3'), findsOneWidget);
    // The one in front is already first.
    expect(find.byTooltip('Show this one first'), findsNothing);
    // And with three of three there is no room for another.
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('picture b'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    expect(removed, ['b']);
    await tester.tap(find.byTooltip('Show this one first'));
    expect(first, ['b']);
  });

  testWidgets('what cannot be removed has no button for it', (tester) async {
    await pump(
      tester,
      ImageCarousel(
        images: [image('a')],
        onRemove: (_) {},
        canRemove: (id) => id != 'a',
      ),
    );
    expect(find.byTooltip('Remove'), findsNothing);
  });
}
