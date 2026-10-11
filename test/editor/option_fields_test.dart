import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/style_settings.dart';

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
    expect(find.text('Too long'), findsOneWidget);
    // Means nothing until it is to move along.
    expect(find.text('Moves'), findsNothing);

    redraw(() => values = {...values, 'overflow': 'scroll'});
    await tester.pump();
    expect(find.text('Moves'), findsOneWidget);

    await tester.tap(find.byTooltip('More').first);
    await tester.pump();
    expect(values['speed'], 50);
    // Set back to the usual, nothing is kept for it.
    await tester.tap(find.byTooltip('Less').first);
    await tester.pump();
    expect(values.containsKey('speed'), isFalse);
  });

  testWidgets('the form for a look is made from the properties it takes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var style = <String, Object?>{'color': '#ff0000'};
    Widget form(List<String> keys) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => StyleSettings(
              keys: keys,
              style: style,
              onChanged: (key, value) =>
                  setState(() => style = withStyle(style, {key: value})),
            ),
          ),
        ),
      ),
    );
    // Only what it takes is offered.
    await tester.pumpWidget(form(const ['opacity', 'color']));
    expect(find.text('Opacity %'), findsOneWidget);
    expect(find.text('Colour'), findsOneWidget);
    expect(find.text('Background'), findsNothing);
    expect(find.text('Letter size'), findsNothing);

    // Solid until it is made less so; the rest of the look is left be.
    expect(find.text('100'), findsOneWidget);
    await tester.tap(find.byTooltip('Less'));
    await tester.pump();
    expect(style, {'color': '#ff0000', 'opacity': 95});
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(style, {'color': '#ff0000'});

    // Everything a box and text take, each drawn by the kind it is.
    await tester.pumpWidget(form(const [...boxStyle, ...textStyle]));
    for (final prop in styleProps) {
      expect(find.text(prop.label), findsOneWidget, reason: prop.key);
    }
    expect(find.text('Each corner by itself'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('every kind of widget says what can be set, each under its own key', () {
    for (final kind in WidgetKind.values) {
      final keys = [for (final option in kind.options) option.key];
      expect(keys.toSet(), hasLength(keys.length), reason: kind.name);
    }
  });
}
