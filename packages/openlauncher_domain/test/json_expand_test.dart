import 'package:openlauncher_domain/json/json_decode.dart';
import 'package:openlauncher_domain/json/json_expand.dart';
import 'package:test/test.dart';

Object? expanded(String text, {List<DefsLevel> levels = const []}) =>
    expandJson(
      decodeJson(text, mode: .jsonc),
      levels: levels,
      source: 'x',
    );

const pack = DefsLevel('pack', {
  'heading': {'fontSize': 28, 'color': '#fff'},
  'box': {'radius': 16, 'fill': '#123'},
});

void main() {
  group(r'$use', () {
    test('is the chunk, with the other keys written over it', () {
      expect(
        expanded(
          r'{"a": {"$use": "heading", "fontSize": 20, "weight": 7}}',
          levels: [pack],
        ),
        {
          'a': {'fontSize': 20, 'color': '#fff', 'weight': 7},
        },
      );
    });

    test('null removes a key, a list replaces a list, objects merge', () {
      final levels = [
        const DefsLevel('t', {
          'c': {
            'a': 1,
            'list': [1, 2],
            'deep': {'x': 1, 'y': 2},
          },
        }),
      ];
      expect(
        expanded(
          r'{"$use": "c", "a": null, "list": [3], "deep": {"y": null, "z": 3}}',
          levels: levels,
        ),
        {
          'list': [3],
          'deep': {'x': 1, 'z': 3},
        },
      );
    });

    test(r'takes parameters, declared with $params', () {
      final levels = [
        const DefsLevel('t', {
          'button': {
            r'$params': {'label': 'Toggle', 'count': 1},
            'text': '{{param.label}}',
            'count': '{{param.count}}',
            'with': {'entity': '{{row.id}}'},
          },
        }),
      ];
      expect(
        expanded(
          r'[{"$use": "button"}, {"$use": "button", "params": {"label": "On", "count": 5}}]',
          levels: levels,
        ),
        [
          {
            'text': 'Toggle',
            'count': 1,
            'with': {'entity': '{{row.id}}'},
          },
          {
            'text': 'On',
            'count': 5,
            'with': {'entity': '{{row.id}}'},
          },
        ],
      );
    });

    test('a parameter nobody declared is refused', () {
      expect(
        () => expanded(r'{"$use": "box", "params": {"x": 1}}', levels: [pack]),
        throwsA(
          isA<JsonExpandError>().having(
            (e) => e.message,
            'message',
            contains('has no parameter "x"'),
          ),
        ),
      );
    });

    test('uses another chunk from where it was written', () {
      final levels = [
        const DefsLevel('type', {
          'card': {r'$use': 'box', 'fill': '#000'},
        }),
        pack,
      ];
      expect(expanded(r'{"$use": "card"}', levels: levels), {
        'radius': 16,
        'fill': '#000',
      });
    });

    test('the nearest definition wins, the file\'s own first', () {
      final levels = [
        const DefsLevel('type', {
          'box': {'radius': 1},
        }),
        pack,
      ];
      expect(expanded(r'{"$use": "box"}', levels: levels), {'radius': 1});
      expect(
        expanded(
          r'{"$defs": {"box": {"radius": 2}}, "in": {"$use": "box"}}',
          levels: levels,
        ),
        {
          'in': {'radius': 2},
        },
      );
    });

    test('an unknown name says so, and where', () {
      expect(
        () => expanded(r'{"a": [{}, {"$use": "nope"}]}', levels: [pack]),
        throwsA(
          isA<JsonExpandError>().having(
            (e) => e.message,
            'message',
            startsWith('x: /a/1: "nope" is not defined'),
          ),
        ),
      );
    });

    test('chunks that use each other in a circle are refused', () {
      expect(
        () => expanded(
          r'{"$defs": {"a": {"$use": "b"}, "b": {"$use": "a"}}, "x": {"$use": "a"}}',
        ),
        throwsA(
          isA<JsonExpandError>().having(
            (e) => e.message,
            'message',
            contains('circle'),
          ),
        ),
      );
    });

    test('a chunk that grows without end is refused', () {
      final doubling = StringBuffer(r'{"$defs": {"l0": {"v": 1}');
      for (var level = 1; level <= 30; level++) {
        doubling.write(
          ', "l$level": {"a": {"\$use": "l${level - 1}"}, '
          '"b": {"\$use": "l${level - 1}"}}',
        );
      }
      doubling.write(r'}, "x": {"$use": "l30"}}');
      expect(
        () => expanded(doubling.toString()),
        throwsA(
          isA<JsonExpandError>().having(
            (e) => e.message,
            'message',
            contains('grows past'),
          ),
        ),
      );
    });

    test('a list chunk must be spread', () {
      expect(
        () => expanded(
          r'{"$use": "l"}',
          levels: [
            const DefsLevel('t', {
              'l': [1],
            }),
          ],
        ),
        throwsA(isA<JsonExpandError>()),
      );
    });
  });

  group(r'$spread', () {
    const levels = [
      DefsLevel('t', {
        'pair': [
          {'n': 1},
          {r'$use': 'box'},
        ],
        'box': {'radius': 4},
      }),
    ];

    test('puts the items of a list chunk in its place', () {
      expect(expanded(r'[0, {"$spread": "pair"}, 9]', levels: levels), [
        0,
        {'n': 1},
        {'radius': 4},
        9,
      ]);
    });

    test('is refused anywhere but on its own in a list', () {
      for (final text in [
        r'{"$spread": "pair"}',
        r'[{"$spread": "pair", "x": 1}]',
        r'[{"$spread": "box"}]',
      ]) {
        expect(
          () => expanded(text, levels: levels),
          throwsA(isA<JsonExpandError>()),
          reason: text,
        );
      }
    });
  });

  test(r'$schema, $comment and $defs are dropped; slots are left alone', () {
    expect(
      expanded(
        r'{"$schema": "u", "$comment": "c", "$defs": {}, "a": "{{row.x}}", "b": {"$comment": "d", "v": 1}}',
      ),
      {
        'a': '{{row.x}}',
        'b': {'v': 1},
      },
    );
  });

  test('a lone parameter slot keeps its type', () {
    expect(
      fillParameters(
        {'a': '{{param.n}}', 'b': 'x{{param.n}}y', 'c': '{{row.n}}'},
        {'n': 3},
      ),
      {'a': 3, 'b': 'x3y', 'c': '{{row.n}}'},
    );
  });

  test(r'defs files hold their chunks under $defs', () {
    final level = defsLevelOf({
      r'$schema': 'u',
      r'$defs': {'a': 1},
    }, 'defs.jsonc');
    expect(level.defs, {'a': 1});
    expect(
      () => defsLevelOf({r'$defs': 4}, 'defs.jsonc'),
      throwsA(isA<JsonExpandError>()),
    );
  });
}
