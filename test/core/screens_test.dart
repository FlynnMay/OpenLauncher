import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/media/media_dirs.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  Screen screen(String id, [Node Function(Node root)? change]) {
    final root = Screen.empty(id).root;
    return Screen(id: id, root: change?.call(root) ?? root);
  }

  Future<ProviderContainer> launcher(LauncherConfig config) async {
    final c = ProviderContainer(
      overrides: [
        ...packOverrides,
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(const [], const []),
        ),
        configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
        mediaPathProvider.overrideWith(
          (ref) async =>
              (use, id) => '/${use.folder}/$id',
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(currentScreenProvider, (_, _) {});
    c.listen(wallpapersProvider, (_, _) {});
    await c.read(layoutViewProvider.future);
    await c.read(mediaPathProvider.future);
    return c;
  }

  test('the launcher opens on its startup screen, and Back goes to the screen '
      'before', () async {
    final c = await launcher(
      LauncherConfig(
        layout: Layout(
          inbox: '',
          screens: [screen('a'), screen('b')],
          startup: const Startup('b'),
        ).normalised(),
      ),
    );
    String? shown() => c.read(currentScreenProvider)?.id;
    expect(shown(), 'b');
    final screens = c.read(shownScreensProvider.notifier);
    c.read(overlaysProvider.notifier).open(const OpenOverlay('x'));
    screens.open('a');
    expect(shown(), 'a');
    // What was open over the screen closes with it.
    expect(c.read(overlaysProvider), isEmpty);
    expect(screens.back(), isTrue);
    expect(shown(), 'b');
    expect(screens.back(), isFalse);
    // Not remembered, unless startup says so.
    expect((await c.read(configProvider.future)).lastScreen, isNull);
  });

  test('a startup that remembers opens on the screen shown last', () async {
    final c = await launcher(
      LauncherConfig(
        layout: Layout(
          inbox: '',
          screens: [screen('a'), screen('b')],
          startup: const Startup('a', remember: true),
        ).normalised(),
        lastScreen: 'b',
      ),
    );
    expect(c.read(currentScreenProvider)?.id, 'b');
    c.read(shownScreensProvider.notifier).open('a');
    await pumpEventQueue();
    expect((await c.read(configProvider.future)).lastScreen, 'a');
  });

  test('a screen with a Wallpaper has its own, else the launcher\'s', () async {
    final c = await launcher(
      LauncherConfig(
        wallpapers: const ['/w.png'],
        layout: Layout(
          inbox: '',
          screens: [
            screen('a'),
            screen(
              'b',
              (root) => root.withModule(wallpaperModule.name, {
                'files': ['x.png', 'y.mp4'],
                'every': '5',
              }),
            ),
            screen('c', (root) => root.withModule(wallpaperModule.name, {})),
          ],
          startup: const Startup('a'),
        ).normalised(),
      ),
    );
    List<String> paths() => [
      for (final wallpaper in c.read(wallpapersProvider)) wallpaper.path,
    ];
    expect(paths(), ['/w.png']);
    final screens = c.read(shownScreensProvider.notifier);
    screens.open('b');
    expect(paths(), ['/wallpaper/x.png', '/wallpaper/y.mp4']);
    expect(c.read(wallpaperEveryProvider), 5);
    // With none of its own, a plain background.
    screens.open('c');
    expect(paths(), isEmpty);
  });

  group('saved in files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('config'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileConfigStore store() => FileConfigStore(dir: () async => dir);
    Object? read(String path) =>
        jsonDecode(File('${dir.path}/$path').readAsStringSync());

    final config = LauncherConfig(
      layout: Layout(
        inbox: 'a/root',
        screens: [screen('a'), screen('b')],
        startup: const Startup('a'),
      ).normalised(),
      prefabs: [
        Prefab(
          id: 'me:bar',
          name: 'Bar',
          root: const Node(id: 'bar'),
        ),
      ],
    );

    test('each screen and prefab has a file, listed in config.json', () async {
      await store().save(config);
      final json = read('config.json')! as Map;
      expect(json['layout']['screens'], ['a', 'b']);
      expect(json['prefabs'], ['me:bar']);
      expect((read('screens/a.json')! as Map)['id'], 'a');
      expect((read('prefabs/me%3Abar.json')! as Map)['name'], 'Bar');
      final again = await store().load();
      expect(jsonEncode(again.toJson()), jsonEncode(config.toJson()));

      // What is no longer there loses its file.
      await store().save(
        config.copyWith(
          layout: config.layout.copyWith(
            screens: [config.layout.screens.first],
          ),
        ),
      );
      expect(File('${dir.path}/screens/b.json').existsSync(), isFalse);
      expect(File('${dir.path}/screens/a.json').existsSync(), isTrue);
    });

    test('one file holding everything is split when read', () async {
      final whole = config.toJson();
      File('${dir.path}/config.json').writeAsStringSync(jsonEncode(whole));
      final read = await store().load();
      expect(jsonEncode(read.toJson()), jsonEncode(whole));
      expect(File('${dir.path}/screens/b.json').existsSync(), isTrue);
    });

    test('a file that cannot be read is kept and left out', () async {
      await store().save(config);
      File('${dir.path}/screens/b.json').writeAsStringSync('{not json');
      final read = await store().load();
      expect(read.layout.screens.map((one) => one.id), ['a']);
      expect(File('${dir.path}/screens/b.json.corrupt').existsSync(), isTrue);
    });
  });
}
