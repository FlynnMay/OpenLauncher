import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/sources.dart';
import 'package:openlauncher/core/values/values.dart';

/// A pack whose source cannot be asked until its host is set, as Home
/// Assistant's is.
void main() {
  final hub = Pack.fromJson({
    'id': 'hub',
    'name': 'Hub',
    'settings': {
      'host': {'type': 'text', 'format': 'url', 'required': true},
      'token': {'type': 'text', 'secret': true, 'required': true},
    },
  })!;
  final generator = Generator.fromJson({
    'from': 'states',
    'entity': {'id': 'hub:light/{{row.id}}', 'label': '{{row.name}}'},
  })!;

  var asked = 0;

  ProviderContainer container(Map<String, Object?> settings) {
    asked = 0;
    final container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(packSettings: {'hub': settings})),
        ),
        packsProvider.overrideWith((ref) async => [hub]),
        secretStoreProvider.overrideWithValue(
          MemorySecretStore({
            'hub': {'token': 's3cret'},
          }),
        ),
        packContentsProvider.overrideWith(
          (ref) async => [
            PackContents(
              hub,
              sources: {
                'states': const Source('{{settings.host}}/states')
                    .inPack('hub'),
              },
              generators: {'lights': generator},
            ),
          ],
        ),
        feedFetcherProvider.overrideWithValue(
          (feed) async => [
            if (++asked > 0) {'id': 'a', 'name': 'Lamp'},
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<String>> labels(ProviderContainer c) async => [
    for (final entity
        in await c
            .read(packEntitiesProvider.future)
            .timeout(const Duration(seconds: 5)))
      entity.label,
  ];

  Future<void> set(ProviderContainer c, Map<String, Object?> settings) =>
      c.read(configProvider.notifier).patch({
        'packSettings': {'hub': settings},
      });

  test(
    'a pack that is not set up gives nothing, and does not hold up the rest',
    () async {
      final c = container(const {});
      final held = c.listen(packEntitiesProvider, (_, _) {});
      addTearDown(held.close);
      await c.read(configProvider.future);
      expect(await labels(c), isEmpty);
    },
  );

  test('setting a pack up and taking its address away both answer', () async {
    final c = container(const {});
    final held = c.listen(packEntitiesProvider, (_, _) {});
    addTearDown(held.close);
    await c.read(configProvider.future);
    expect(await labels(c), isEmpty);
    await set(c, {'host': 'http://hub.test'});
    await pumpEventQueue();
    expect(await labels(c), ['Lamp']);
    await set(c, const {});
    await pumpEventQueue();
    expect(await labels(c), isEmpty);
  });
}
