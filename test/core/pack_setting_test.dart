import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';

void main() {
  test('a setting is a key with the field it asks for', () {
    final setting = PackSetting.fromJson('host', {
      'label': 'Server',
      'type': 'text',
      'format': 'url',
      'required': true,
    })!;
    expect(setting.label, 'Server');
    expect(setting.required, isTrue);
    expect(setting.accepts('https://ha.local'), isTrue);
    expect(setting.accepts('ha.local'), isFalse);
    expect(PackSetting.fromJson('host', setting.toJson()), setting);
  });

  test('a setting without a label is called by its key', () {
    expect(PackSetting.fromJson('unit', {'type': 'toggle'})!.label, 'unit');
  });

  test('a secret is a setting of the secret type', () {
    expect(
      PackSetting.fromJson('token', {'type': 'text', 'secret': true})!.secret,
      isTrue,
    );
  });

  test('what is not a field, or has a bad key, is dropped', () {
    expect(PackSetting.fromJson('host', {'type': 'tick'}), isNull);
    expect(PackSetting.fromJson('bad key', {'type': 'text'}), isNull);
    expect(
      PackSetting.listFromJson({
        'a': {'type': 'text'},
        'b': 'text',
      }).map((setting) => setting.key),
      ['a'],
    );
  });

  test('a choice from the web keeps what choosing a row keeps', () {
    final setting = PackSetting.fromJson('place', {
      'type': 'choice',
      'from': {
        'url': 'http://x.test/find?name={{query}}',
        'label': '{{row.name}}',
        'keep': {'latitude': '{{row.latitude}}'},
      },
    })!;
    expect(setting.accepts({'name': 'Perth', 'latitude': 1}), isTrue);
    expect(setting.accepts({'name': 'Perth'}), isFalse);
    expect(setting.accepts('Perth'), isFalse);
  });
}
