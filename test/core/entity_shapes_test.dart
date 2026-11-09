import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/entities/entities.dart';

void main() {
  final all = StateProvider<List<Entity>>((ref) => const []);

  Entity light(String label, String state) => Entity(
    id: 'hub:light/a',
    category: 'light',
    label: label,
    data: {'state': state},
    prefab: 'hub:tile',
  );

  test('the shapes stay put while only values change', () async {
    final container = ProviderContainer(
      overrides: [entitiesProvider.overrideWith((ref) async => ref.watch(all))],
    );
    addTearDown(container.dispose);
    container.read(all.notifier).state = [light('Lamp', 'on')];
    final first = await container.read(entityShapesProvider.future);
    expect(first.single.data, isEmpty);
    expect(first.single.prefab, 'hub:tile');

    container.read(all.notifier).state = [light('Lamp', 'off')];
    expect(await container.read(entityShapesProvider.future), same(first));

    container.read(all.notifier).state = [light('Desk lamp', 'off')];
    expect(
      (await container.read(entityShapesProvider.future)).single.label,
      'Desk lamp',
    );
  });
}
