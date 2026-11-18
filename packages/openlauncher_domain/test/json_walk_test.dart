import 'package:openlauncher_domain/json/json_walk.dart';
import 'package:openlauncher_domain/values/template_fill.dart';
import 'package:test/test.dart';

void main() {
  test('fills templates at any depth and keeps a lone slot typed', () {
    expect(
      fillSlots(
        {
          'a': '{{row.n}}',
          'b': ['x {{row.name}}', 1, null],
          'c': {'d': '{{other.x}}'},
        },
        {'row'},
        (root) => {'n': 3, 'name': 'a'},
      ),
      {
        'a': 3,
        'b': ['x a', 1, null],
        'c': {'d': '{{other.x}}'},
      },
    );
  });

  test('an entry can be treated on its own', () {
    expect(
      walkJson(
        {
          'name': 'x',
          'inner': {'name': 'y'},
        },
        onText: (text) => text.toUpperCase(),
        onEntry: (key, value, walk) => key == 'name' ? value : walk(value),
      ),
      {
        'name': 'x',
        'inner': {'name': 'y'},
      },
    );
  });
}
