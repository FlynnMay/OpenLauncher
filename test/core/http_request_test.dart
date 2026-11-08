import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/core/sources/sources.dart';
import 'package:openlauncher/core/values/values.dart';

void main() {
  final hub = Pack.fromJson({
    'id': 'hub',
    'settings': {
      'host': {'type': 'url'},
      'token': {'type': 'secret'},
    },
    'auth': {
      'ha': {
        'host': '{{settings.host}}',
        'headers': {'Authorization': 'Bearer {{settings.token}}'},
      },
    },
  })!;
  final toggle = Entity(
    id: 'hub:light/desk',
    category: 'light',
    label: 'Desk',
    data: const {'entity_id': 'light.desk'},
    actions: const {
      'toggle': EntityAction(
        run: '{{settings.host}}/api/services/light/toggle',
        bound: {
          'method': 'POST',
          'auth': 'ha',
          'body': {'entity_id': '{{self.entity_id}}'},
        },
        then: [
          EntityAction(
            run: 'launcher://sources/fetch',
            bound: {'source': 'states'},
          ),
        ],
      ),
    },
  );

  final states = Source(
    '{{settings.host}}/api/states',
    auth: 'ha',
    every: 3600,
  ).inPack('hub');

  late List<http.Request> sent;
  late int status;
  late ProviderContainer container;

  setUp(() {
    sent = [];
    status = 200;
    container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(
            LauncherConfig(
              packSettings: {
                'hub': {'host': 'http://ha.local:8123'},
              },
            ),
          ),
        ),
        packsProvider.overrideWith((ref) async => [hub]),
        packContentsProvider.overrideWith(
          (ref) async => [
            PackContents(hub, sources: {'states': states}),
          ],
        ),
        secretStoreProvider.overrideWithValue(
          MemorySecretStore({
            'hub': {'token': 's3cret'},
          }),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            sent.add(request);
            return http.Response('{}', status);
          }),
        ),
        feedFetcherProvider.overrideWithValue((feed) async {
          sent.add(http.Request(feed.method, feed.address));
          return const <String, Object?>{};
        }),
        entitiesProvider.overrideWith((ref) async => [toggle]),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<String?> act() => container
      .read(actionRunnerProvider)
      .run(Act('toggle', {entityArg: 'hub:light/desk'}));

  test(
    'an entity action posts the filled body with the pack signature',
    () async {
      await act();
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(
        sent.single.url,
        Uri.parse('http://ha.local:8123/api/services/light/toggle'),
      );
      expect(sent.single.headers['Authorization'], 'Bearer s3cret');
      expect(jsonDecode(sent.single.body), {'entity_id': 'light.desk'});
    },
  );

  test(
    'a follow up that fetches a source runs once the action is done',
    () async {
      final watching = container.listen(
        sourceValueProvider((id: 'hub:states', source: states)),
        (_, _) {},
      );
      addTearDown(watching.close);
      await container.read(
        sourceValueProvider((id: 'hub:states', source: states)).future,
      );
      expect(sent.map((r) => (r.method, r.url.path)), [('GET', '/api/states')]);
      await act();
      await container.pump();
      await container.read(
        sourceValueProvider((id: 'hub:states', source: states)).future,
      );
      expect(sent.map((r) => (r.method, r.url.path)), [
        ('GET', '/api/states'),
        ('POST', '/api/services/light/toggle'),
        ('GET', '/api/states'),
      ]);
    },
  );

  test('anything but a 2xx is an error', () async {
    status = 401;
    final watching = container.listen(
      sourceValueProvider((id: 'hub:states', source: states)),
      (_, _) {},
    );
    addTearDown(watching.close);
    await container.read(
      sourceValueProvider((id: 'hub:states', source: states)).future,
    );
    final before = sent.length;
    await expectLater(act(), throwsA(isA<http.ClientException>()));
    // The follow up is not run for an action that failed: only the POST.
    expect(sent.length, before + 1);
  });

  test('a request to another host is not signed, and not made', () async {
    await expectLater(
      container
          .read(operationsRegistryProvider)['https://']!
          .run(
            const OperationRun({
              'method': 'POST',
              'auth': 'ha',
              'url': 'http://evil.test/',
            }, entityId: 'hub:light/desk'),
          ),
      throwsA(isA<FormatException>()),
    );
    expect(sent, isEmpty);
  });

  test('needs an address', () {
    final operation = container.read(operationsRegistryProvider)['https://']!;
    expect(
      operation.run(const OperationRun({'method': 'GET'})),
      throwsA(isA<BadArguments>()),
    );
    expect(
      operation.run(const OperationRun({'url': 'ha.local', 'method': 'GET'})),
      throwsA(isA<FormatException>()),
    );
  });
}
