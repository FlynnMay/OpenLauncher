import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

LauncherCard _card(String name, {String? icon}) => LauncherCard(
  id: 'app:$name',
  kind: CardKind.app,
  target: name,
  label: name,
  iconPath: icon,
);

void main() {
  group('arrangeCards', () {
    test('sorts inputs first, then apps, each alphabetically', () {
      const hdmi = LauncherCard(
        id: 'input:x/HW1',
        kind: CardKind.input,
        target: 'x/HW1',
        label: 'HDMI 1',
      );
      final cards = arrangeCards([
        _card('Plex'),
        _card('alpha'),
        hdmi,
        _card('Zed'),
      ], LauncherConfig());
      expect(cards.map((c) => c.label), ['HDMI 1', 'alpha', 'Plex', 'Zed']);
    });

    test('icon override replaces the automatic icon', () {
      final cards = arrangeCards([
        _card('Plex', icon: '/auto.png'),
      ], LauncherConfig(iconOverrides: {'app:Plex': '/custom.png'}));
      expect(cards.single.iconPath, '/custom.png');
      expect(cards.single.wideIcon, isTrue);
    });
  });

  group('providers', () {
    late MemoryConfigStore store;
    late FakeLauncherPlatform platform;
    late ProviderContainer container;

    setUp(() {
      store = MemoryConfigStore();
      platform = FakeLauncherPlatform([
        InstalledApp(packageName: 'a', label: 'A', isBanner: false),
        InstalledApp(packageName: 'b', label: 'B', isBanner: false),
      ], []);
      container = ProviderContainer(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          launcherPlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(container.dispose);
      // Keep the providers alive for the duration of the test.
      container.listen(layoutViewProvider, (_, _) {});
    });

    /// The apps and inputs on the home screen, in order. The launcher's
    /// own Settings card is there too, after them.
    Future<List<LauncherCard>> cards() async => [
      for (final entry in (await container.read(
        layoutViewProvider.future,
      )).home.root.contents)
        if ((entry as CardEntry).card.kind != CardKind.action) entry.card,
    ];

    Future<List<String>> ids() async =>
        (await cards()).map((c) => c.id).toList();

    test('config changes are persisted and reflected in cards', () async {
      expect(await ids(), ['app:a', 'app:b']);

      final config = container.read(configProvider.notifier);
      await config.setLayout(Layout.initial(['app:b', 'app:a']));
      expect(await ids(), ['app:b', 'app:a']);
      expect(store.config.layout.home.items.map((i) => i.ref), [
        'app:b',
        'app:a',
      ]);

      // Removed cards are gone until they are placed again; they are not
      // mistaken for new apps.
      await config.removeCard('app:b');
      expect(await ids(), ['app:a']);
      expect(store.config.layout.removed, {'app:b'});
      await config.setLayout(Layout.initial(['app:b', 'app:a']));
      expect(await ids(), ['app:b', 'app:a']);
      expect(store.config.layout.removed, isEmpty);

      await config.setIconOverride('app:a', '/x.png');
      expect(store.config.iconOverrides, {'app:a': '/x.png'});
      await config.setIconOverride('app:a', null);
      expect(store.config.iconOverrides, isEmpty);
    });

    test('cards refresh when the device reports a package change', () async {
      expect(await ids(), ['app:a', 'app:b']);
      platform.apps = [
        ...platform.apps,
        InstalledApp(packageName: 'c', label: 'C', isBanner: false),
      ];
      platform.notifyAppsChanged();
      await pumpEventQueue();
      expect(await ids(), ['app:a', 'app:b', 'app:c']);
    });

    test('TV inputs become cards, refresh, and switch input', () async {
      platform.inputs = [
        TvInput(id: 'tv/HW15', label: 'HDMI 1', kind: TvInputKind.hdmi),
      ];
      platform.notifyInputsChanged();
      await pumpEventQueue();
      expect(await ids(), ['input:tv/HW15', 'app:a', 'app:b']);

      await container.read(cardActionsProvider).launch((await cards()).first);
      expect(platform.launched, ['tv/HW15']);
    });

    test('launching an app card goes to the platform', () async {
      await container.read(cardActionsProvider).launch((await cards()).last);
      expect(platform.launched, ['b']);
    });

    test('quick actions follow the saved menu and the kind of card', () async {
      platform.inputs = [
        TvInput(id: 'tv/HW15', label: 'HDMI 1', kind: TvInputKind.hdmi),
      ];
      platform.notifyInputsChanged();
      await pumpEventQueue();
      final actions = container.read(cardActionsProvider);
      final [input, app, _] = await cards();

      expect(await actions.actionsFor(app), CardAction.values);
      // An input is not an app: nothing to stop or uninstall.
      expect(await actions.actionsFor(input), [
        CardAction.open,
        CardAction.remove,
      ]);
      await container.read(configProvider.notifier).setContextMenu([
        CardAction.uninstall,
        CardAction.open,
      ]);
      expect(await actions.actionsFor(app), [
        CardAction.uninstall,
        CardAction.open,
      ]);

      expect(await actions.perform(CardAction.uninstall, app), isNull);
      expect(await actions.perform(CardAction.forceStop, app), contains('A'));
      expect(platform.appActions, ['uninstall a', 'stop a']);

      // Without ADB the TV's own screen is opened instead.
      platform.canForceStop = false;
      expect(
        await actions.perform(CardAction.forceStop, app),
        contains('Force stop'),
      );
      expect(platform.appActions.last, 'info a');

      await actions.perform(CardAction.remove, app);
      expect(await ids(), ['input:tv/HW15', 'app:b']);
    });
  });

  group('inputArtworkSvg', () {
    test('badges the port number from the label', () {
      final svg = inputArtworkSvg(TvInputKind.hdmi, 'HDMI 2');
      expect(svg, startsWith('<svg '));
      expect(svg, contains('>2</text>'));
      // Two digits widen the circle into a pill.
      expect(
        inputArtworkSvg(TvInputKind.hdmi, 'HDMI 12'),
        contains('width="36.0"'),
      );
    });

    test('no badge without a number, and a picture per kind', () {
      final pictures = {
        for (final kind in TvInputKind.values) inputArtworkSvg(kind, 'TV'),
      };
      expect(pictures, hasLength(TvInputKind.values.length));
      expect(pictures.any((svg) => svg.contains('<text')), isFalse);
    });
  });
}
