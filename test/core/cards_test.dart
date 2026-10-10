import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards_provider.dart';
import 'package:openlauncher/core/cards/input_artwork.dart';
import 'package:openlauncher/core/cards/launcher_card.dart';
import 'package:openlauncher/core/config/config_controller.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
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
    final available = [_card('Plex'), _card('alpha'), _card('Zed')];

    test('sorts alphabetically, ignoring case, with no config', () {
      final cards = arrangeCards(available, const LauncherConfig());
      expect(cards.map((c) => c.label), ['alpha', 'Plex', 'Zed']);
    });

    test('ordered cards come first, the rest follow alphabetically', () {
      final cards = arrangeCards(
        available,
        const LauncherConfig(order: ['app:Zed', 'app:gone', 'app:Plex']),
      );
      expect(cards.map((c) => c.label), ['Zed', 'Plex', 'alpha']);
    });

    test('unlisted inputs come before unlisted apps', () {
      const hdmi = LauncherCard(
        id: 'input:x/HW1',
        kind: CardKind.input,
        target: 'x/HW1',
        label: 'HDMI 1',
      );
      final cards = arrangeCards([
        ...available,
        hdmi,
      ], const LauncherConfig(order: ['app:Zed']));
      expect(cards.map((c) => c.label), ['Zed', 'HDMI 1', 'alpha', 'Plex']);
    });

    test('drops hidden cards', () {
      final cards = arrangeCards(
        available,
        const LauncherConfig(hidden: {'app:Plex'}),
      );
      expect(cards.map((c) => c.label), ['alpha', 'Zed']);
    });

    test('icon override replaces the automatic icon', () {
      final cards = arrangeCards([
        _card('Plex', icon: '/auto.png'),
      ], const LauncherConfig(iconOverrides: {'app:Plex': '/custom.png'}));
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
      container.listen(cardsProvider, (_, _) {});
    });

    Future<List<String>> ids() async =>
        (await container.read(cardsProvider.future)).map((c) => c.id).toList();

    test('config changes are persisted and reflected in cards', () async {
      expect(await ids(), ['app:a', 'app:b']);

      final config = container.read(configProvider.notifier);
      await config.setOrder(['app:b', 'app:a']);
      expect(await ids(), ['app:b', 'app:a']);
      expect(store.config.order, ['app:b', 'app:a']);

      await config.setHidden('app:b', true);
      expect(await ids(), ['app:a']);
      await config.setHidden('app:b', false);
      expect(await ids(), ['app:b', 'app:a']);

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

      final cards = await container.read(cardsProvider.future);
      await container.read(cardActionsProvider).launch(cards.first);
      expect(platform.launched, ['tv/HW15']);
    });

    test('launching an app card goes to the platform', () async {
      final cards = await container.read(cardsProvider.future);
      await container.read(cardActionsProvider).launch(cards.last);
      expect(platform.launched, ['b']);
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

  test('LauncherConfig survives a JSON round trip', () {
    const config = LauncherConfig(
      order: ['app:a'],
      hidden: {'app:b'},
      iconOverrides: {'app:a': '/x.png'},
      wallpaper: '/w.mp4',
    );
    final copy = LauncherConfig.fromJson(config.toJson());
    expect(copy.wallpaper, '/w.mp4');
    expect(copy.copyWith(order: []).wallpaper, '/w.mp4');
    expect(copy.copyWith(wallpaper: null).wallpaper, isNull);
    expect(copy.order, config.order);
    expect(copy.hidden, config.hidden);
    expect(copy.iconOverrides, config.iconOverrides);
    expect(LauncherConfig.fromJson(const {}).order, isEmpty);
  });
}
