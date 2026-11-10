import 'package:openlauncher_domain/fields/field_spec.dart';
import 'package:openlauncher_domain/nodes/field.dart';
import 'package:test/test.dart';

FieldSpec spec(Map<String, Object?> json) => FieldSpec.fromJson(json)!;

void main() {
  groupTests();
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

class _Premade {
  static FieldLibrary library(Map<String, Map<String, Object?>> premade) =>
      FieldLibrary(premade);
}

void groupTests() {
  Map<String, Object?> address({Map<String, Object?> more = const {}}) => {
    'type': 'group',
    'label': 'Address',
    'columns': 4,
    'fields': {
      'street': {'type': 'text', 'span': 2},
      'city': {'type': 'text'},
      'postcode': {'type': 'text', 'maxLength': 4},
    },
    ...more,
  };

  group('a group', () {
    test('holds fields by name and is a map of their values', () {
      final home = spec(address());
      expect(home.fields.keys, ['street', 'city', 'postcode']);
      expect(home.columns, 4);
      expect(home.fields['street']!.span, 2);
      expect(home.accepts({'street': 'Main St', 'postcode': '6000'}), isTrue);
      expect(home.accepts({'suburb': 'x'}), isFalse);
      expect(home.accepts({'postcode': '60000'}), isFalse);
      expect(home.accepts('Main St'), isFalse);
      expect(FieldSpec.fromJson(home.toJson()), home);
    });

    test('without fields it is not a field', () {
      expect(FieldSpec.fromJson({'type': 'group', 'fields': {}}), isNull);
      expect(
        FieldSpec.fromJson({
          'type': 'group',
          'fields': {
            'bad name': {'type': 'text'},
          },
        }),
        isNull,
      );
    });

    test('a column count and span stay within the grid', () {
      expect(spec(address(more: {'columns': 99})).columns, 12);
      expect(spec(address(more: {'columns': 0})).columns, 1);
    });

    test('reaches every field in it by path, secrets included', () {
      final login = spec({
        'type': 'group',
        'fields': {
          'user': {'type': 'text'},
          'token': {'type': 'text', 'secret': true},
          'more': {
            'type': 'group',
            'secret': true,
            'fields': {
              'pin': {'type': 'number'},
            },
          },
        },
      });
      expect(
        [for (final leaf in login.leaves('login')) (leaf.path, leaf.secret)],
        [
          ('login.user', false),
          ('login.token', true),
          ('login.more.pin', true),
        ],
      );
      // A secret is kept apart, so it is never part of the value.
      expect(login.accepts({'user': 'me'}), isTrue);
      expect(login.accepts({'token': 'abc'}), isFalse);
      expect(login.accepts({'more': {}}), isFalse);
    });

    test('reads a value by its path', () {
      final values = {
        'address': {'postcode': '6000'},
      };
      expect(FieldSpec.valueAt(values, 'address.postcode'), '6000');
      expect(FieldSpec.valueAt(values, 'address.city'), isNull);
      expect(FieldSpec.valueAt(values, 'address.postcode.x'), isNull);
    });

    test('is told about the whole form to show a part of itself', () {
      final part = spec({
        'type': 'text',
        'visible': '{{values.kind == "home" && root.advanced}}',
      });
      expect(part.shows({'kind': 'home'}, root: {'advanced': true}), isTrue);
      expect(part.shows({'kind': 'home'}, root: {'advanced': false}), isFalse);
    });
  });

  group('flat names', () {
    test('make or join the group they start with', () {
      final settings = FieldSpec.expandNames({
        'address.street': {'type': 'text'},
        'address.city': {'type': 'text'},
        'name': {'type': 'text'},
      });
      expect(settings.keys, ['address', 'name']);
      final home = FieldSpec.fromJson(settings['address'])!;
      expect(home.type, FieldType.group);
      expect(home.fields.keys, ['street', 'city']);
    });

    test('add to a group that is written out, wherever it comes', () {
      final settings = FieldSpec.expandNames({
        'address.postcode': {'type': 'text'},
        'address': {
          'type': 'group',
          'label': 'Home',
          'fields': {
            'street': {'type': 'text'},
          },
        },
      });
      final home = FieldSpec.fromJson(settings['address'])!;
      expect(home.label, 'Home');
      expect(home.fields.keys, ['street', 'postcode']);
    });

    test('go as deep as they are dotted', () {
      final home = spec({
        'type': 'group',
        'fields': {
          'a.b.c': {'type': 'text'},
        },
      });
      expect(home.fields['a']!.fields['b']!.fields['c']!.type, FieldType.text);
    });
  });

  group('a premade field', () {
    final library = _Premade.library({
      'hub:place': {
        'extends': 'choice',
        'label': 'Place',
        r'$params': {
          'country': {'default': 'au'},
        },
        'from': {
          'url': 'http://x.test/find?q={{query}}&cc={{param.country}}',
          'label': '{{row.name}}',
        },
      },
      'hub:address': {
        'extends': 'group',
        'label': 'Address',
        'columns': 4,
        'fields': {
          'street': {'type': 'text', 'span': 2},
          'city': {'type': 'place'},
          'postcode': {'type': 'text'},
        },
      },
      'hub:home': {'extends': 'address', 'label': 'Home address'},
      'other:name': {'extends': 'text', 'maxLength': 3},
      'hub:loop': {'extends': 'loop'},
    });

    FieldSpec? read(Object? json, [String pack = 'hub']) =>
        FieldSpec.fromJson(json, library: library, pack: pack);

    test('is a primitive with its settings filled in', () {
      final place = read({'type': 'place'})!;
      expect(place.type, FieldType.choice);
      expect(place.label, 'Place');
      expect(place.from!.source.address, contains('cc=au'));
      // What is not its own to fill is left for later.
      expect(place.from!.source.address, contains('{{query}}'));
    });

    test('takes parameters, and is written over by its use', () {
      final place = read({
        'type': 'place',
        'label': 'Where',
        'params': {'country': 'nz'},
      })!;
      expect(place.label, 'Where');
      expect(place.from!.source.address, contains('cc=nz'));
    });

    test('can be a group of other premade fields', () {
      final home = read({'type': 'address'})!;
      expect(home.fields.keys, ['street', 'city', 'postcode']);
      expect(home.fields['city']!.type, FieldType.choice);
      expect(home.fields['street']!.span, 2);
    });

    test('builds on another, and its use changes a part of it', () {
      final home = read({
        'type': 'home',
        'fields': {
          'postcode': {'maxLength': 4},
          'country': {'type': 'text'},
        },
      })!;
      expect(home.label, 'Home address');
      expect(home.fields['postcode']!.maxLength, 4);
      expect(home.fields.keys, ['street', 'city', 'postcode', 'country']);
    });

    test('one part of a group can stand alone', () {
      final postcode = read({'type': 'address.postcode'})!;
      expect(postcode.type, FieldType.text);
      final city = read({'type': 'hub:address.city', 'label': 'Town'})!;
      expect(city.type, FieldType.choice);
      expect(city.label, 'Town');
      expect(read({'type': 'address.nothing'}), isNull);
    });

    test('is found in another pack by its name, else by the bare name', () {
      expect(read({'type': 'other:name'})!.maxLength, 3);
      expect(read({'type': 'name'}), isNull);
      expect(read({'type': 'name'}, 'other')!.maxLength, 3);
      expect(read({'type': 'missing'}), isNull);
    });

    test('is refused when it only loops', () {
      expect(read({'type': 'loop'}), isNull);
    });
  });
}
