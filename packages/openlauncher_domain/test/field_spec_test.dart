import 'package:openlauncher_domain/fields/field_spec.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:test/test.dart';

FieldSpec spec(Map<String, Object?> json) => FieldSpec.fromJson(json)!;

void main() {
  group('text', () {
    test('keeps to its length, pattern and format', () {
      final code = spec({
        'type': 'text',
        'minLength': 2,
        'maxLength': 4,
        'pattern': r'^[a-z]+$',
      });
      expect(code.accepts('abc'), isTrue);
      expect(code.accepts('a'), isFalse);
      expect(code.accepts('abcde'), isFalse);
      expect(code.accepts('ab1'), isFalse);
      expect(code.accepts(''), isTrue);
      final web = spec({'type': 'text', 'format': 'url'});
      expect(web.accepts('https://ha.local:8123'), isTrue);
      expect(web.accepts('ha.local'), isFalse);
    });

    test('a pattern that does not compile is not a field', () {
      expect(FieldSpec.fromJson({'type': 'text', 'pattern': '('}), isNull);
    });
  });

  test('a number keeps to the bounds it has', () {
    final volume = spec({'type': 'number', 'min': 0, 'max': 10});
    expect(volume.accepts(5), isTrue);
    expect(volume.accepts(11), isFalse);
    expect(volume.accepts('5'), isFalse);
    expect(spec({'type': 'number'}).accepts(-4000), isTrue);
    expect(FieldSpec.fromJson({'type': 'number', 'min': 3, 'max': 1}), isNull);
  });

  test('a toggle is a bool and nothing else', () {
    final on = spec({'type': 'toggle'});
    expect(on.accepts(true), isTrue);
    expect(on.accepts('true'), isFalse);
  });

  group('choice', () {
    final options = {'a': 'Apple', 'b': 'Bean'};

    test('takes one of its options, written as a map or a list', () {
      final one = spec({'type': 'choice', 'options': options});
      expect(one.accepts('a'), isTrue);
      expect(one.accepts('c'), isFalse);
      expect(one.accepts(['a']), isFalse);
      final listed = spec({
        'type': 'choice',
        'options': ['x', 'y'],
      });
      expect(listed.options, {'x': 'x', 'y': 'y'});
    });

    test('several are a list within the counts', () {
      final several = spec({
        'type': 'choice',
        'options': options,
        'multiple': true,
        'maxChoices': 1,
      });
      expect(several.accepts(['a']), isTrue);
      expect(several.accepts(['a', 'b']), isFalse);
      expect(several.accepts('a'), isFalse);
      expect(several.accepts(['z']), isFalse);
    });

    test('a look suits only its kind of choice', () {
      expect(
        spec({'type': 'choice', 'options': options, 'as': 'radio'}).look,
        ChoiceLook.radio,
      );
      expect(
        spec({'type': 'choice', 'options': options, 'as': 'checks'}).look,
        isNull,
      );
      expect(
        spec({
          'type': 'choice',
          'options': options,
          'multiple': true,
          'as': 'dropdown',
        }).look,
        ChoiceLook.multiDropdown,
      );
    });

    test('without options it is not a field', () {
      expect(FieldSpec.fromJson({'type': 'choice'}), isNull);
    });
  });

  group('a choice from the web', () {
    final json = {
      'type': 'choice',
      'label': 'Place',
      'from': {
        'url': 'http://x.test/find?name={{query}}',
        'rows': 'results',
        'label': '{{row.name}}, {{row.country}}',
        'where': '{{row.rank > 1}}',
        'group': '{{row.country}}',
        'keep': {'latitude': '{{row.latitude}}', 'name': 'ignored'},
      },
    };

    test('lists a row, under a heading, and keeps a map', () {
      final from = spec(json).from!;
      final hit = from.hitFrom({
        'name': 'Perth',
        'country': 'Australia',
        'rank': 3,
        'latitude': -31.95,
      })!;
      expect(hit.title, 'Perth, Australia');
      expect(hit.group, 'Australia');
      expect(hit.value, {'name': 'Perth, Australia', 'latitude': -31.95});
      expect(from.hitFrom({'name': 'Low', 'rank': 1}), isNull);
    });

    test('without keep, a row keeps its value, else its label', () {
      Map<String, Object?> from(Map<String, Object?> more) => {
        ...json,
        'from': {'url': 'http://x.test/find', 'label': '{{row.name}}', ...more},
      };
      expect(spec(from({})).from!.hitFrom({'name': 'Perth'})!.value, 'Perth');
      expect(
        spec(from({'value': '{{row.id}}'})).from!
            .hitFrom({'name': 'Perth', 'id': 7})!
            .value,
        7,
      );
    });

    test('takes what choosing a row could have kept', () {
      final place = spec(json);
      expect(place.accepts({'name': 'Perth', 'latitude': 1}), isTrue);
      expect(place.accepts({'name': 'Perth'}), isFalse);
      expect(place.accepts('Perth'), isFalse);
      final several = spec({...json, 'multiple': true});
      expect(
        several.accepts([
          {'name': 'Perth', 'latitude': 1},
        ]),
        isTrue,
      );
    });

    test('asks at one character, none when filtering', () {
      expect(spec(json).from!.leastTyped, 1);
      final filter = spec({
        ...json,
        'from': {...(json['from'] as Map<String, Object?>), 'on': 'filter'},
      });
      expect(filter.from!.leastTyped, 0);
    });

    test('is written back as it was read', () {
      final place = spec(json);
      expect(FieldSpec.fromJson(place.toJson()), place);
    });

    test('a source without a label is not a field', () {
      expect(
        FieldSpec.fromJson({
          'type': 'choice',
          'from': {'url': 'http://x.test/find'},
        }),
        isNull,
      );
    });
  });

  test('a field shows when its visible template reads true', () {
    final tall = spec({
      'type': 'number',
      'visible': '{{values.unit == "metric"}}',
    });
    expect(tall.shows({'unit': 'metric'}), isTrue);
    expect(tall.shows({'unit': 'imperial'}), isFalse);
    expect(spec({'type': 'toggle'}).shows({}), isTrue);
  });

  test('a default that does not fit is dropped', () {
    expect(spec({'type': 'toggle', 'default': true}).defaultValue, isTrue);
    expect(spec({'type': 'toggle', 'default': 'yes'}).defaultValue, isNull);
  });

  test('several chosen or none at all is blank', () {
    expect(FieldSpec.isBlank([]), isTrue);
    expect(FieldSpec.isBlank(''), isTrue);
    expect(FieldSpec.isBlank(['a']), isFalse);
    expect(FieldSpec.isBlank(false), isFalse);
  });

  test('any kind of field can be a secret, which has no default', () {
    for (final type in ['text', 'number', 'toggle']) {
      final hidden = spec({'type': type, 'secret': true, 'default': 1});
      expect(hidden.secret, isTrue, reason: type);
      expect(hidden.defaultValue, isNull, reason: type);
      expect(FieldSpec.fromJson(hidden.toJson()), hidden);
    }
    final pin = spec({'type': 'number', 'secret': true, 'min': 1000});
    expect(pin.accepts(1234), isTrue);
    expect(pin.accepts('1234'), isFalse);
    expect(spec({'type': 'text'}).secret, isFalse);
    // It used to be a type of its own.
    expect(FieldSpec.fromJson({'type': 'secret'}), isNull);
  });

  test('a secret is kept as text, or as JSON when it is not text', () {
    expect(FieldSpec.storedAs('abc'), 'abc');
    expect(FieldSpec.storedAs(1234), '1234');
    expect(FieldSpec.storedAs(false), 'false');
    expect(FieldSpec.storedAs(['a', 'b']), '["a","b"]');
  });
}
