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
        controller.patch({'wallpaperEvery': 5}),
        controller.patch({
          'toasts': {'seconds': 9},
        }),
        controller.patch({
          'names': {'a': 'One'},
        }),
      ]);

      final config = await container.read(configProvider.future);
      expect(config.wallpaperEvery, 5);
      expect(config.toasts.seconds, 9);
      expect(config.names, {'a': 'One'});
    },
  );
}
