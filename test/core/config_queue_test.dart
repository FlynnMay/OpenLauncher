import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';

void main() {
  test(
    'changes started together all land, none reads a stale config',
    () async {
      final container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(LauncherConfig()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(configProvider.future);
      final controller = container.read(configProvider.notifier);

      await Future.wait([
        controller.setName('a', 'One'),
        controller.setName('b', 'Two'),
        controller.setName('c', 'Three'),
      ]);

      final names = (await container.read(configProvider.future)).names;
      expect(names, {'a': 'One', 'b': 'Two', 'c': 'Three'});
    },
  );
}
