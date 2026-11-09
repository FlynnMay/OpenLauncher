import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';

void main() {
  final json = {
    'label': 'Place',
    'type': 'search',
    'search': {'url': 'http://x.test/find?name={{query}}', 'rows': 'results'},
    'title': '{{row.name}}, {{row.country}}',
    'keep': {'latitude': '{{row.latitude}}', 'name': 'ignored'},
  };

  test('a search says where to look, how a hit is listed and what is kept', () {
    final setting = PackSetting.fromJson('place', json)!;
    expect(setting.search!.rows, 'results');
    final chosen = setting.chosenFrom({
      'name': 'Perth',
      'country': 'Australia',
      'latitude': -31.95,
    })!;
    expect(chosen.title, 'Perth, Australia');
    expect(chosen.value, {'name': 'Perth, Australia', 'latitude': -31.95});
    expect(PackSetting.fromJson('place', setting.toJson()), setting);
  });

  test('a search without a source or a title is not a setting', () {
    expect(PackSetting.fromJson('place', {...json, 'search': null}), isNull);
    expect(PackSetting.fromJson('place', {...json, 'title': ''}), isNull);
  });

  test('only a chosen hit is a value of a search', () {
    final setting = PackSetting.fromJson('place', json)!;
    expect(setting.accepts({'name': 'Perth', 'latitude': 1}), isTrue);
    expect(setting.accepts({'name': 'Perth'}), isFalse);
    expect(setting.accepts('Perth'), isFalse);
  });
}
