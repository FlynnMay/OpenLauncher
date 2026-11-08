import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

void main() {
  Future<ProviderContainer> launcher(List<String> screens) async {
    final c = ProviderContainer(
      overrides: [
        ...launcherOverrides,
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

  group('VariableService, called with no operation in between', () {
    test(
      'sets on the node it names, else on the component that asked',
      () async {
        final c = await launcher(['home']);
        final variables = c.read(variableServiceProvider);
        await variables.set(
          variable: 'on',
          value: true,
          of: 'menu',
          component: 'card',
        );
        await variables.set(variable: 'on', value: false, component: 'card');
        await variables.set(variable: 'on', value: 1);
        expect(c.read(runtimeVarsProvider), {
          'menu': {'on': true},
          'card': {'on': false},
        });
      },
    );

    test('evaluates a text with {{ }} in it as it is set', () async {
      final c = await launcher(['home']);
      await c
          .read(variableServiceProvider)
          .set(variable: 'n', value: '{{1 + 2}}', component: 'card');
      expect('${c.read(runtimeVarsProvider)['card']?['n']}', '3');
    });
  });

  group('AccessService, called with no operation in between', () {
    Future<(ProviderContainer, FakeLauncherPlatform)> tv() async {
      final platform = FakeLauncherPlatform(const [], const []);
      final c = ProviderContainer(
        overrides: [launcherPlatformProvider.overrideWithValue(platform)],
      );
      addTearDown(c.dispose);
      return (c, platform);
    }

    test('sends the user to the TV\'s own screen', () async {
      final (c, platform) = await tv();
      expect(
        await c.read(accessServiceProvider).change(Access.homeButton),
        isNull,
      );
      expect(platform.accessChanged, [Access.homeButton]);
    });

    test('says so when the TV has no screen for it', () async {
      final (c, platform) = await tv();
      platform.noAccessScreen = true;
      final message = await c
          .read(accessServiceProvider)
          .change(Access.homeButton);
      expect(message, startsWith('This TV has no screen for it\n'));
      expect(platform.accessChanged, isEmpty);
    });
  });

  group('the services over the TV, called with no operation in between', () {
    late FakeLauncherPlatform platform;
    late ProviderContainer c;

    setUp(() {
      platform = FakeLauncherPlatform(const [], const []);
      c = ProviderContainer(
        overrides: [launcherPlatformProvider.overrideWithValue(platform)],
      );
      addTearDown(c.dispose);
    });

    test('apps are opened, shown and uninstalled by package', () async {
      final apps = c.read(appServiceProvider);
      expect(await apps.launch('fake.plex'), isNull);
      await apps.showInfo('fake.plex');
      await apps.uninstall('fake.kodi');
      expect(platform.launched, ['fake.plex']);
      expect(platform.appActions, ['info fake.plex', 'uninstall fake.kodi']);
    });

    test('an input is switched to by id', () async {
      await c.read(inputServiceProvider).switchTo('fake/HW2');
      expect(platform.launched, ['fake/HW2']);
    });

    test('a command goes to whatever is playing', () async {
      await c.read(mediaServiceProvider).send(MediaCommand.playPause);
      expect(platform.mediaCommands, [MediaCommand.playPause]);
    });

    test("the TV's settings are opened", () async {
      await c.read(tvSettingsServiceProvider).open();
      expect(platform.tvSettingsOpened, 1);
    });
  });
}
