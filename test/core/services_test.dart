import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/services/services.dart';

import '../support/packs.dart';

void main() {
  Future<ProviderContainer> launcher(List<String> screens) async {
    final c = ProviderContainer(
      overrides: [
        ...packOverrides,
        configStoreProvider.overrideWithValue(
          MemoryConfigStore(
            LauncherConfig(
              layout: Layout(
                inbox: '',
                screens: [for (final id in screens) Screen.empty(id)],
              ).normalised(),
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(configProvider.future);
    return c;
  }

  Future<List<String>> screensOf(ProviderContainer c) async => [
    for (final screen in (await c.read(configProvider.future)).layout.screens)
      screen.id,
  ];

  group('ScreenService, called with no operation in between', () {
    test('adds a screen under a free id, named as asked', () async {
      final c = await launcher(['home']);
      final screens = c.read(screenServiceProvider);
      expect(await screens.add(name: 'Games'), 'Screen "games" was added.');
      expect(await screens.add(name: 'Games'), 'Screen "games-2" was added.');
      expect(await screensOf(c), ['home', 'games', 'games-2']);
      final layout = (await c.read(configProvider.future)).layout;
      expect(layout.screen('games')?.root.name, 'Games');
    });

    test('renames, copies and removes the screen it is told', () async {
      final c = await launcher(['home', 'other']);
      final screens = c.read(screenServiceProvider);
      expect(await screens.rename(id: 'other', name: 'Else'), isNull);
      expect(
        (await c.read(configProvider.future)).layout.screen('other')?.root.name,
        'Else',
      );
      expect(
        await screens.duplicate(id: 'other'),
        'Screen "other-2" was added.',
      );
      expect(await screensOf(c), ['home', 'other', 'other-2']);
      expect(
        await screens.remove(id: 'other-2'),
        'Screen "other-2" was removed.',
      );
      expect(await screensOf(c), ['home', 'other']);
    });

    test('refuses what there is no screen for, and the last screen', () async {
      final c = await launcher(['home']);
      final screens = c.read(screenServiceProvider);
      expect(await screens.open('nowhere'), 'There is no screen "nowhere".');
      expect(await screens.remove(id: 'nowhere'), 'There is no such screen.');
      expect(
        await screens.startup(id: 'nowhere'),
        'There is no screen "nowhere".',
      );
      expect(await screens.remove(id: 'home'), 'The last screen stays.');
      expect(await screensOf(c), ['home']);
    });

    test(
      'sets the startup screen and whether the last one is remembered',
      () async {
        final c = await launcher(['home', 'other']);
        final screens = c.read(screenServiceProvider);
        expect(await screens.startup(id: 'other', remember: true), isNull);
        var startup = (await c.read(configProvider.future)).layout.startup;
        expect((startup.screen, startup.remember), ('other', true));
        // What is not given is kept.
        await screens.startup(remember: false);
        startup = (await c.read(configProvider.future)).layout.startup;
        expect((startup.screen, startup.remember), ('other', false));
      },
    );
  });
}
