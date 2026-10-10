import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';

void main() {
  ProviderContainer withConfig(LauncherConfig config) {
    final container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the first wallpaper is shown when they do not take turns', () async {
    final container = withConfig(
      LauncherConfig(wallpapers: const ['/a.png', '/b.mp4', '/c.txt']),
    );
    await container.read(configProvider.future);
    // What is not a picture or a video is not a wallpaper.
    expect(container.read(wallpapersProvider), hasLength(2));
    expect(container.read(wallpaperProvider)?.path, '/a.png');
  });

  test('with turns, each wallpaper stays for the minutes given', () {
    fakeAsync((async) {
      final container = withConfig(
        LauncherConfig(
          wallpapers: const ['/a.png', '/b.mp4'],
          wallpaperEvery: 10,
        ),
      );
      final shown = <String?>[];
      container.listen(
        wallpaperProvider,
        (_, next) => shown.add(next?.path),
        fireImmediately: true,
      );
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 25));
      expect(shown.whereType<String>().toList(), [
        '/a.png',
        '/b.mp4',
        '/a.png',
      ]);
    });
  });
}
