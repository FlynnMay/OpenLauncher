import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';
import 'package:openlauncher_domain/nodes/field.dart';

/// A form of fields written as a pack writes them.
class _Form {
  _Form(
    this.tester,
    this.specs, {
    this.find,
    this.secret,
    Map<String, Object?> start = const {},
  }) : values = {...start};

  final WidgetTester tester;
  final Map<String, Map<String, Object?>> specs;
  final Future<List<FieldHit>> Function(String text)? find;
  final FieldSecret? secret;
  Map<String, Object?> values;

  Future<void> show() => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              children: optionFields(
                options: [
                  for (final MapEntry(:key, :value) in specs.entries)
                    FieldSpec.fromJson(value)!
                        .toField(key, find: find, secretState: secret),
                ],
                values: values,
                onChanged: (next) => setState(() => values = next),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final fruit = {'a': 'Apple', 'b': 'Bean', 'c': 'Cherry'};

  testWidgets('a few options are radio buttons, picked one at a time', (
    tester,
  ) async {
    final form = _Form(tester, {
      'fruit': {'type': 'choice', 'label': 'Fruit', 'options': fruit},
    });
    await form.show();
    expect(find.byType(RadioChoices), findsOneWidget);
    await tester.tap(find.text('Bean'));
    await tester.pump();
    expect(form.values, {'fruit': 'b'});
    await tester.tap(find.text('Cherry'));
    await tester.pump();
    expect(form.values, {'fruit': 'c'});
  });

  testWidgets('many options, or a look asked for, are a dropdown', (
    tester,
  ) async {
    final form = _Form(tester, {
      'many': {
        'type': 'choice',
        'options': [for (var n = 0; n < 6; n++) 'option $n'],
      },
      'asked': {'type': 'choice', 'options': fruit, 'as': 'dropdown'},
    });
    await form.show();
    expect(find.byType(RadioChoices), findsNothing);
    expect(find.byType(ChoiceBox<String>), findsNWidgets(2));
  });

  testWidgets('a segmented choice is a row of buttons', (tester) async {
    final form = _Form(tester, {
      'unit': {'type': 'choice', 'options': fruit, 'as': 'segmented'},
    });
    await form.show();
    await tester.tap(find.text('Apple'));
    await tester.pump();
    expect(form.values, {'unit': 'a'});
  });

  testWidgets('several options are checkboxes that save a list', (
    tester,
  ) async {
    final form = _Form(tester, {
      'fruit': {
        'type': 'choice',
        'options': fruit,
        'multiple': true,
        'maxChoices': 2,
      },
    });
    await form.show();
    await tester.tap(find.text('Cherry'));
    await tester.pump();
    await tester.tap(find.text('Apple'));
    await tester.pump();
    // Kept in the order they are listed.
    expect(form.values, {
      'fruit': ['a', 'c'],
    });
    // At the most, so the third cannot be ticked.
    await tester.tap(find.text('Bean'));
    await tester.pump();
    expect(form.values['fruit'], ['a', 'c']);
    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.tap(find.text('Cherry'));
    await tester.pump();
    expect(form.values.containsKey('fruit'), isFalse);
  });

  testWidgets('several options as chips, or in a menu', (tester) async {
    final form = _Form(tester, {
      'chips': {
        'type': 'choice',
        'options': fruit,
        'multiple': true,
        'as': 'chips',
      },
      'menu': {
        'type': 'choice',
        'options': fruit,
        'multiple': true,
        'as': 'dropdown',
      },
    });
    await form.show();
    await tester.tap(find.widgetWithText(FilterChip, 'Bean'));
    await tester.pump();
    expect(form.values['chips'], ['b']);

    await tester.tap(find.byType(MultiDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cherry').last);
    await tester.pumpAndSettle();
    // The menu stays open to tick another.
    await tester.tap(find.text('Apple').last);
    await tester.pumpAndSettle();
    expect(form.values['menu'], ['a', 'c']);
  });

  testWidgets('a text that does not fit is marked and not kept', (
    tester,
  ) async {
    final form = _Form(tester, {
      'host': {'type': 'text', 'label': 'Host', 'format': 'url'},
    });
    await form.show();
    await tester.enterText(find.byType(TextField), 'ha.local');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Not a valid value'), findsOneWidget);
    expect(form.values, isEmpty);
    await tester.enterText(find.byType(TextField), 'http://ha.local');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(form.values, {'host': 'http://ha.local'});
  });

  testWidgets('a field applies only while its visible template reads true', (
    tester,
  ) async {
    final form = _Form(tester, {
      'advanced': {'type': 'toggle', 'label': 'Advanced'},
      'port': {
        'type': 'number',
        'label': 'Port',
        'visible': '{{values.advanced}}',
      },
    });
    await form.show();
    expect(find.text('Port'), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pump();
    expect(find.text('Port'), findsOneWidget);
  });

  testWidgets('a secret shows as dots and is cleared only once agreed', (
    tester,
  ) async {
    var cleared = 0;
    final replaced = <String>[];
    final form = _Form(
      tester,
      {
        'token': {'type': 'secret', 'label': 'Token'},
      },
      secret: FieldSecret(
        isSet: true,
        replace: (text) async => replaced.add(text),
        clear: () async => cleared++,
      ),
    );
    await form.show();
    expect(
      find.text('Saved on the TV. Type a new one to replace it.'),
      findsOneWidget,
    );
    expect(find.text('Replace'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(find.text('Replace'));
    await tester.pump();
    expect(replaced, ['abc']);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(cleared, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
    expect(form.values, isEmpty);
  });

  group('a choice from the web', () {
    final from = {
      'url': 'http://x.test/find?name={{query}}',
      'label': '{{row.name}}',
    };
    Map<String, Map<String, Object?>> place(Map<String, Object?> more) => {
      'place': {
        'type': 'choice',
        'label': 'Place',
        ...more,
        'from': {...from, ...?(more['from'] as Map<String, Object?>?)},
      },
    };

    FieldHit hit(String name, [String group = '']) =>
        (title: name, group: group, value: name);

    testWidgets('asks after a pause in typing, and picks one', (tester) async {
      final asked = <String>[];
      final form = _Form(
        tester,
        place({
          'from': {'debounce': 100},
        }),
        find: (text) async {
          asked.add(text);
          return [hit('Perth'), hit('Perth Amboy')];
        },
      );
      await form.show();
      await tester.enterText(find.byType(TextField), 'Per');
      await tester.enterText(find.byType(TextField), 'Perth');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(asked, ['Perth']);
      await tester.tap(find.text('Perth Amboy'));
      await tester.pump();
      expect(form.values, {'place': 'Perth Amboy'});
      expect(find.widgetWithText(InputChip, 'Perth Amboy'), findsOneWidget);
      // Choosing another replaces it.
      await tester.enterText(find.byType(TextField), 'Perth');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Perth'));
      await tester.pump();
      expect(form.values, {'place': 'Perth'});
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(form.values, isEmpty);
    });

    testWidgets('waits for the characters it needs', (tester) async {
      final asked = <String>[];
      final form = _Form(
        tester,
        place({
          'from': {'minChars': 3, 'debounce': 0},
        }),
        find: (text) async {
          asked.add(text);
          return [hit('Perth')];
        },
      );
      await form.show();
      await tester.enterText(find.byType(TextField), 'Pe');
      await tester.pump(const Duration(milliseconds: 10));
      expect(asked, isEmpty);
      await tester.enterText(find.byType(TextField), 'Per');
      await tester.pump(const Duration(milliseconds: 10));
      expect(asked, ['Per']);
    });

    testWidgets('asks on Enter when it is told to', (tester) async {
      final asked = <String>[];
      final form = _Form(
        tester,
        place({
          'from': {'on': 'enter'},
        }),
        find: (text) async {
          asked.add(text);
          return [hit('Perth')];
        },
      );
      await form.show();
      await tester.enterText(find.byType(TextField), 'Perth');
      await tester.pump(const Duration(seconds: 1));
      expect(asked, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(asked, ['Perth']);
    });

    testWidgets('asks once, then filters what it found', (tester) async {
      final asked = <String>[];
      final form = _Form(
        tester,
        place({
          'from': {'on': 'filter'},
        }),
        find: (text) async {
          asked.add(text);
          return [hit('Apple'), hit('Banana')];
        },
      );
      await form.show();
      await tester.pump();
      expect(find.text('Banana'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'app');
      await tester.pump();
      expect(find.text('Banana'), findsNothing);
      expect(find.text('Apple'), findsOneWidget);
      expect(asked, ['']);
    });

    testWidgets('several can be picked, and unpicked, under headings', (
      tester,
    ) async {
      final form = _Form(
        tester,
        place({
          'multiple': true,
          'from': {'debounce': 0},
        }),
        find: (text) async => [
          hit('Perth', 'Australia'),
          hit('Paris', 'France'),
        ],
      );
      await form.show();
      await tester.enterText(find.byType(TextField), 'P');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.text('France'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Perth'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Paris'));
      await tester.pump();
      expect(form.values, {
        'place': ['Perth', 'Paris'],
      });
      await tester.tap(find.widgetWithText(ListTile, 'Perth'));
      await tester.pump();
      expect(form.values, {
        'place': ['Paris'],
      });
    });

    testWidgets('says when the asking failed', (tester) async {
      final form = _Form(
        tester,
        place({
          'from': {'debounce': 0},
        }),
        find: (text) async => throw Exception('no network'),
      );
      await form.show();
      await tester.enterText(find.byType(TextField), 'P');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.textContaining('no network'), findsOneWidget);
    });
  });
}
