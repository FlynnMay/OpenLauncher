import 'package:openlauncher_domain/json/json_decode.dart';
import 'package:test/test.dart';

void main() {
  group('strict', () {
    test('reads plain JSON', () {
      expect(decodeJson('{"a": [1, 2]}'), {
        'a': [1, 2],
      });
    });

    test('refuses a comment', () {
      expect(
        () => decodeJson('{\n  // note\n  "a": 1\n}', source: 'x.json'),
        throwsA(
          isA<JsonDecodeError>()
              .having((e) => e.file, 'file', 'x.json')
              .having((e) => e.line, 'line', 2),
        ),
      );
    });

    test('refuses a trailing comma', () {
      expect(() => decodeJson('[1, 2,]'), throwsA(isA<JsonDecodeError>()));
    });
  });

  group('jsonc', () {
    test('the extension picks the mode', () {
      expect(JsonMode.ofPath('a/b.jsonc'), JsonMode.jsonc);
      expect(JsonMode.ofPath('a/b.json'), JsonMode.strict);
      expect(decodeJson('{"a": 1, // note\n}', source: 'b.jsonc'), {'a': 1});
      expect(
        () => decodeJson('{"a": 1, // note\n}', source: 'b.json'),
        throwsA(isA<JsonDecodeError>()),
      );
    });

    test('line and block comments', () {
      expect(
        decodeJson('/* head\n  more */ {"a": /* mid */ 1} // tail', mode: .jsonc),
        {'a': 1},
      );
    });

    test('comment markers inside strings stay', () {
      expect(
        decodeJson(r'{"u": "http://x/*y*/", "q": "a\"//b"}', mode: .jsonc),
        {'u': 'http://x/*y*/', 'q': 'a"//b'},
      );
    });

    test('trailing commas in objects and lists, but not inside strings', () {
      expect(
        decodeJson('{"a": [1, 2, ], "b": "x,}",\n}', mode: .jsonc),
        {
          'a': [1, 2],
          'b': 'x,}',
        },
      );
    });

    test('a comment ending the text with no new line', () {
      expect(decodeJson('1 // done', mode: .jsonc), 1);
    });

    test('an unclosed block comment says where it starts', () {
      expect(
        () => decodeJson('{\n  /* open\n}', source: 'p.jsonc'),
        throwsA(
          isA<JsonDecodeError>()
              .having((e) => e.line, 'line', 2)
              .having((e) => e.column, 'column', 3),
        ),
      );
    });

    test('errors keep their position in the source', () {
      expect(
        () => decodeJson('{\n  // note\n  "a": ?\n}', source: 'p.jsonc'),
        throwsA(
          isA<JsonDecodeError>()
              .having((e) => e.line, 'line', 3)
              .having((e) => e.message, 'message', startsWith('p.jsonc:3:')),
        ),
      );
    });
  });

  test('names without their JSON extension', () {
    expect(withoutJsonExtension('light.jsonc'), 'light');
    expect(withoutJsonExtension('light.json'), 'light');
    expect(withoutJsonExtension('light.svg'), 'light.svg');
    expect(isJsonPath('a.jsonc') && isJsonPath('a.json'), isTrue);
    expect(isJsonPath('a.svg'), isFalse);
  });
}
