import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/sources.dart';

void main() {
  final hub = Pack.fromJson({
    'id': 'hub',
    'name': 'Hub',
    'settings': {
      'host': {'label': 'Address', 'type': 'url', 'required': true},
      'token': {'label': 'Token', 'type': 'secret', 'required': true},
    },
    'auth': {
      'ha': {
        'host': '{{settings.host}}',
        'headers': {'Authorization': 'Bearer {{settings.token}}'},
      },
    },
  })!;

  Future<HttpFeed> request(
    Source source, {
    Map<String, Object?> settings = const {'host': 'http://ha.local:8123'},
    Map<String, String> secrets = const {'token': 's3cret'},
  }) {
    final container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(packSettings: {'hub': settings})),
        ),
        packsProvider.overrideWith((ref) async => [hub]),
        secretStoreProvider.overrideWithValue(
          MemorySecretStore({'hub': secrets}),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(
      FutureProvider(
        (ref) => requestOf(ref, (id: 'hub:states', source: source)),
        retry: (_, _) => null,
      ).future,
    );
  }

  Source states({String? auth, Object? body, String method = 'GET'}) => Source(
    '{{settings.host}}/api/states',
    every: 10,
    method: method,
    auth: auth,
    body: body,
  ).inPack('hub');

  test('fills the address from the pack settings and signs it', () async {
    final feed = await request(states(auth: 'ha'));
    expect(feed.address, Uri.parse('http://ha.local:8123/api/states'));
    expect(feed.headers, {'Authorization': 'Bearer s3cret'});
    expect(feed.every, 10);
  });

  test('a changed setting is another fetch', () async {
    final first = await request(states());
    final second = await request(
      states(),
      settings: const {'host': 'http://other.local'},
    );
    expect(first, isNot(second));
  });

  test('sends a body and method as asked', () async {
    final feed = await request(
      states(method: 'POST', body: {'host': '{{settings.host}}'}),
    );
    expect(feed.method, 'POST');
    expect(feed.body, '{"host":"http://ha.local:8123"}');
  });

  test('waits while a required setting has no value', () async {
    await expectLater(
      request(states(), settings: const {}),
      throwsA(isA<SourceNotReady>()),
    );
    await expectLater(
      request(states(), secrets: const {}),
      throwsA(isA<SourceNotReady>()),
    );
  });

  test('a secret is never read into an address', () async {
    final leaky = Source('http://{{settings.token}}.test/').inPack('hub');
    expect('${(await request(leaky)).address}', isNot(contains('s3cret')));
  });

  test('a profile that is not the address signs nothing', () async {
    final elsewhere = Source('http://evil.test/', auth: 'ha').inPack('hub');
    await expectLater(request(elsewhere), throwsA(isA<SourceNotReady>()));
  });

  test('a source reads its method, auth and body, and writes them back', () {
    final source = Source.fromJson({
      'url': '{{settings.host}}/api/states',
      'method': 'post',
      'auth': 'ha',
      'body': {'a': 1},
    })!;
    expect(
      (source.method, source.auth, source.isTemplate),
      ('POST', 'ha', true),
    );
    expect(Source.fromJson(source.toJson()), source);
    expect(
      Source.fromJson({'url': 'https://x.test', 'method': 'DELETE'}),
      isNull,
    );
  });
}
