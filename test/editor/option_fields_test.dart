import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/editor/option_fields.dart';

void main() {
  testWidgets('a form is made from what a widget says can be set', (
    tester,
  ) async {
    var values = <String, Object?>{'text': 'Hello'};
    late StateSetter redraw;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configStoreProvider.overrideWithValue(MemoryConfigStore())],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  redraw = setState;
                  return Column(
                    children: optionFields(
                      options: WidgetKind.text.options,
                      values: values,
                      onChanged: (next) => setState(() => values = next),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Fills the box'), findsOneWidget);
    // Means nothing until the letters have a size.
    expect(find.text('Too long'), findsNothing);

    await tester.tap(find.byTooltip('More').first);
    await tester.pump();
    expect(values['size'], 8);
    expect(find.text('Too long'), findsOneWidget);
    expect(find.text('Moves'), findsNothing);

    redraw(() => values = {...values, 'overflow': 'scroll'});
    await tester.pump();
    expect(find.text('Moves'), findsOneWidget);

    // Set back to the usual, nothing is kept for it.
    await tester.tap(find.text('Bold'));
    await tester.pump();
    expect(values['bold'], isTrue);
    await tester.tap(find.text('Bold'));
    await tester.pump();
    expect(values.containsKey('bold'), isFalse);
    await tester.tap(find.byTooltip('Less').first);
    await tester.pump();
    expect(values.containsKey('size'), isFalse);
  });

  test('every kind of widget says what can be set, each under its own key', () {
    for (final kind in WidgetKind.values) {
      final keys = [for (final option in kind.options) option.key];
      expect(keys.toSet(), hasLength(keys.length), reason: kind.name);
    }
  });
}
