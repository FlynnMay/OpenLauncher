import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/sources.dart';

void main() {
  final rows = StateProvider<List<Object?>>((ref) => const []);
  final generator = Generator.fromJson({
    'from': 'states',
    'entity': {
      'id': 'hub:light/{{row.id}}',
      'label': '{{settings.prefix}}{{row.name}}',
    },
  })!;

  ProviderContainer containerWith(Map<String, Object?> settings) {
    final container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(LauncherConfig(packSettings: {'hub': settings})),
        ),
        packContentsProvider.overrideWith(
          (ref) async => [
            PackContents(
              const Pack(id: 'hub', name: 'Hub'),
              sources: const {'states': Source('https://hub.test/states')},
              generators: {'lights': generator},
            ),
          ],
        ),
        sourceRowsProvider.overrideWith((ref, at) async => ref.watch(rows)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Map<String, Object?> light(String name) => {'id': 'a', 'name': name};

  test('a poll that changes nothing gives the same list', () async {
    final container = containerWith(const {'prefix': 'My '});
    container.read(rows.notifier).state = [light('Lamp')];
    final first = await container.read(packEntitiesProvider.future);
    expect(first.single.label, 'My Lamp');

    container.read(rows.notifier).state = [light('Lamp')];
    final second = await container.read(packEntitiesProvider.future);
    expect(identical(second, first), isTrue);

    container.read(rows.notifier).state = [light('Desk')];
    final third = await container.read(packEntitiesProvider.future);
    expect(third.single.label, 'My Desk');
  });
}
