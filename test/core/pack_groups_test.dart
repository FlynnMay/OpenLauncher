import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher_domain/fields/field_spec.dart';

void main() {
  final library = FieldLibrary({
    'base:address': {
      'extends': 'group',
      'columns': 4,
      'fields': {
        'street': {'type': 'text', 'span': 2, 'required': true},
        'city': {'type': 'text'},
        'postcode': {'type': 'text'},
      },
    },
  });

  final hub = Pack.fromJson({
    'id': 'hub',
    'settings': {
      'address': {'type': 'base:address', 'label': 'Home'},
      'login.user': {'type': 'text', 'label': 'User', 'required': true},
      'login.token': {
        'type': 'text',
        'label': 'Token',
        'secret': true,
        'required': true,
      },
      'zip': {'type': 'base:address.postcode'},
    },
    'auth': {
      'api': {
        'host': 'http://api.test',
        'headers': {'Authorization': 'Bearer {{settings.login.token}}'},
      },
    },
  }, library: library)!;

  test('settings are groups, premade fields and one part of one', () {
    expect(hub.settings.map((setting) => setting.key), [
      'address',
      'login',
      'zip',
    ]);
    expect(hub.settings[0].spec.fields.keys, ['street', 'city', 'postcode']);
    expect(hub.settings[1].spec.type, FieldType.group);
    expect(hub.settings[2].spec.type, FieldType.text);
  });

  test('is sent to the editor as it is, with nothing left to look up', () {
    final sent = Pack.fromJson(hub.toJson())!;
    expect(sent.settings, hub.settings);
  });

  test('every field with a value of its own has a path', () {
    expect(hub.leaves.map((leaf) => leaf.path), [
      'address.street',
      'address.city',
      'address.postcode',
      'login.user',
      'login.token',
      'zip',
    ]);
    expect(hub.fieldAt('login.token')!.secret, isTrue);
    expect(hub.fieldAt('login.user')!.secret, isFalse);
    expect(hub.fieldAt('login'), isNull);
    expect(hub.hasSecrets, isTrue);
  });

  test('says which required fields have no value, secrets apart', () {
    expect(hub.missing({}, {}), ['address.street', 'User', 'Token']);
    expect(
      hub.missing(
        {
          'address': {'street': 'Main St'},
          'login': {'user': 'me'},
        },
        {'login.token'},
      ),
      isEmpty,
    );
  });

  test('a secret in a group is in the headers, beside the plain settings', () {
    final profile = hub.auth['api']!;
    final target = Uri.parse('http://api.test/x');
    Map<String, String>? headers(Map<String, String> secrets) =>
        profile.headersFor(
          target,
          settings: {
            'login': {'user': 'me'},
          },
          secrets: secrets,
        );
    expect(headers({'login.token': 's3cret'}), {
      'Authorization': 'Bearer s3cret',
    });
    expect(headers({}), isNull);
  });
}
