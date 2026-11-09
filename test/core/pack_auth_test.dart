import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/packs/packs.dart';

void main() {
  final profile = PackAuthProfile.fromJson('ha', {
    'host': '{{settings.host}}',
    'headers': {'Authorization': 'Bearer {{settings.token}}'},
  })!;
  const settings = <String, Object?>{'host': 'http://ha.local:8123'};
  const secrets = {'token': 's3cret'};

  Map<String, String>? headers(
    String url, {
    Map<String, Object?> plain = settings,
    Map<String, String> secret = secrets,
  }) => profile.headersFor(Uri.parse(url), settings: plain, secrets: secret);

  test('fills its headers for a request to its host', () {
    expect(headers('http://ha.local:8123/api/states'), {
      'Authorization': 'Bearer s3cret',
    });
  });

  test('sends nothing to another host, port or scheme', () {
    expect(headers('http://evil.example/api/states'), isNull);
    expect(headers('http://ha.local:9000/api/states'), isNull);
    expect(headers('https://ha.local:8123/api/states'), isNull);
  });

  test('sends nothing while a setting it needs has no value', () {
    expect(headers('http://ha.local:8123/', secret: const {}), isNull);
    expect(headers('http://ha.local:8123/', plain: const {}), isNull);
  });

  test('a secret cannot be the host', () {
    final sneaky = PackAuthProfile.fromJson('x', {
      'host': 'http://{{settings.token}}',
      'headers': {'a': 'b'},
    })!;
    expect(
      sneaky.headersFor(
        Uri.parse('http://s3cret/'),
        settings: const {},
        secrets: secrets,
      ),
      isNull,
    );
  });

  test('a header may read only settings', () {
    final other = PackAuthProfile.fromJson('x', {
      'host': '{{settings.host}}',
      'headers': {'a': '{{nowPlaying.title}}'},
    })!;
    expect(
      other.headersFor(
        Uri.parse('http://ha.local:8123/'),
        settings: settings,
        secrets: secrets,
      ),
      isNull,
    );
  });

  test('a pack reads its profiles and drops unreadable ones', () {
    final pack = Pack.fromJson({
      'id': 'hub',
      'auth': {
        'ha': {
          'host': '{{settings.host}}',
          'headers': {'Authorization': 'Bearer {{settings.token}}'},
        },
        'no headers': {'host': 'x', 'headers': {}},
        'broken': 3,
      },
    })!;
    expect(pack.auth.keys, ['ha']);
    expect(Pack.fromJson(pack.toJson())!.auth, pack.auth);
  });
}
