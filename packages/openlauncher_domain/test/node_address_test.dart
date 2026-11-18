import 'package:openlauncher_domain/nodes/node_names.dart';
import 'package:openlauncher_domain/values/template.dart';
import 'package:test/test.dart';

void main() {
  Set<String> rootsOf(String source) => Template.parse(source).roots;

  String render(String source, Map<String, Object?> values) =>
      Template.parse(source).render((root) => values[root]);

  group('an address in a template', () {
    test('is a pack, a node, its children, a module', () {
      expect(rootsOf('{{homeassistant:light-kitchen.on}}'), {
        'homeassistant:light-kitchen',
      });
      expect(rootsOf('{{card/lines/title.text}}'), {'card/lines/title'});
      expect(rootsOf('{{card/icon#style.padding}}'), {'card/icon#style'});
      expect(rootsOf('{{card#style}}'), {'card#style'});
    });

    test('is looked up whole, then reached into by the path', () {
      final values = {
        'card/icon#style': {'padding': 12},
        'parent/label': {'text': 'Kitchen'},
        'homeassistant:light-kitchen': {'on': true},
      };
      expect(render('{{card/icon#style.padding}}', values), '12');
      expect(render('{{parent/label.text}}', values), 'Kitchen');
      expect(render('{{homeassistant:light-kitchen.on}}', values), 'true');
    });

    test('starts with the words for a place in the tree', () {
      expect(rootsOf('{{self/title.text}} {{parent.url}} {{root#layout}}'), {
        'self/title',
        'parent',
        'root#layout',
      });
    });

    test('is not cut by a trailing mark', () {
      expect(rootsOf('{{a/ 2}}'), {'a'});
      expect(render('{{a/ 2}}', {'a': 6}), '3');
    });

    test('keeps division when it has a space either side', () {
      expect(render('{{a / b}}', {'a': 6, 'b': 3}), '2');
      expect(rootsOf('{{a / b}}'), {'a', 'b'});
      expect(rootsOf('{{a/b}}'), {'a/b'});
    });

    test('works in conditions and calls', () {
      final values = {
        'card/button': {'on': true},
        'level': 3,
      };
      expect(render("{{card/button.on ? 'yes' : 'no'}}", values), 'yes');
      expect(render('{{max(level, 1)}}', values), '3');
    });
  });

  group('names', () {
    test('an id is letters, digits, underscores and hyphens', () {
      for (final id in ['light-kitchen', 'a', 'App_2', '0x']) {
        expect(isNodeId(id), isTrue, reason: id);
      }
      for (final id in [
        '',
        'light.kitchen',
        'a/b',
        'a#b',
        'a:b',
        '-a',
        'a b',
      ]) {
        expect(isNodeId(id), isFalse, reason: id);
      }
    });

    test('self, parent and root are not free', () {
      for (final word in reservedWords) {
        expect(isFreeName(word), isFalse);
      }
      expect(isFreeName('location'), isTrue);
    });
  });
}
