import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/settings/settings.dart';

void main() {
  testWidgets('a form is made from what a component says can be set', (
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
                      options: ComponentRegistry.text.options,
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
    expect(find.text('Overflow'), findsOneWidget);
    // Means nothing until it is to move along.
    expect(find.text('Scroll speed'), findsNothing);

    redraw(() => values = {...values, 'overflow': 'scroll'});
    await tester.pump();
    expect(find.text('Scroll speed'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase').first);
    await tester.pump();
    expect(values['speed'], 50);
    // Set back to the default, nothing is kept for it.
    await tester.tap(find.byTooltip('Decrease').first);
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
    expect(find.text('Font size'), findsNothing);

    // Solid until it is made less so; the rest of the look is left be.
    expect(find.text('100'), findsOneWidget);
    await tester.tap(find.byTooltip('Decrease'));
    await tester.pump();
    expect(style, {'color': '#ff0000', 'opacity': 95});
    await tester.tap(find.byTooltip('Increase'));
    await tester.pump();
    expect(style, {'color': '#ff0000'});

    // Everything a box and text take, each drawn by the kind it is.
    await tester.pumpWidget(form(const [...boxStyle, ...textStyle]));
    for (final prop in stylePropsOf(const [...boxStyle, ...textStyle])) {
      expect(find.text(prop.label), findsOneWidget, reason: prop.key);
    }
    expect(find.text('Individual corners'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A scroll bar's are the rest of them.
    await tester.pumpWidget(form(scrollbarStyle));
    for (final prop in stylePropsOf(scrollbarStyle)) {
      expect(find.text(prop.label), findsOneWidget, reason: prop.key);
    }
    expect(
      {...boxStyle, ...textStyle, ...scrollbarStyle},
      {for (final prop in styleProps) prop.key},
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'every kind of component says what can be set, each under its own key',
    () {
      for (final kind in ComponentRegistry.values) {
        final keys = [for (final option in kind.options) option.key];
        expect(keys.toSet(), hasLength(keys.length), reason: kind.name);
      }
    },
  );

  test('variables go to their form and back as they were', () {
    final variables = {
      'count': const Variable(5),
      'shown': const Variable('{{media.title}}', access: VarAccess.public),
      'icon': const Variable(
        null,
        when: '{{weather.sky}}',
        cases: [VarCase(VarTest.equals, 'rain', 'umbrella')],
        otherwise: 'sun',
      ),
    };
    final form = variablesToForm(variables);
    expect(
      variablesToJson(variablesFromForm(form)),
      variablesToJson(variables),
    );
    // A name is kept to what a template can write; one already there, or
    // none at all, adds nothing.
    expect(
      variablesFromForm([
        ...form,
        {'name': 'my var!'},
        {'name': 'count', 'value': '9'},
        {'name': '  '},
      ]).keys,
      ['count', 'shown', 'icon', 'myvar'],
    );
  });

  testWidgets('a list is added to, set and taken from', (tester) async {
    var acts = <Map<String, Object?>>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configStoreProvider.overrideWithValue(MemoryConfigStore())],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => ListField(
                  option: ComponentOption(
                    'press',
                    'Add action',
                    OptionKind.list,
                    blank: const {'do': 'set'},
                    // What an act may add is what the action lets it.
                    fields: (act) => argOptions(
                      actionsOf('variables', builtInEntities)['set']!.args,
                    ),
                  ),
                  records: acts,
                  onChanged: (next) => setState(() => acts = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('None'), findsOneWidget);
    await tester.tap(find.text('Add action'));
    await tester.pump();
    expect(acts, [
      {'do': 'set'},
    ]);
    // What a `set` is told is offered, and typed as what it reads as.
    await tester.enterText(find.widgetWithText(TextField, 'var'), 'open');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(find.widgetWithText(TextField, 'value'), 'true');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(acts, [
      {'do': 'set', 'var': 'open', 'value': true},
    ]);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pump();
    expect(acts, isEmpty);
  });
}
