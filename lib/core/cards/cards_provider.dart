import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/launcher_platform.dart';
import '../config/config_controller.dart';
import '../config/launcher_config.dart';
import 'input_artwork.dart';
import 'launcher_card.dart';

/// Installed apps as reported by the device, refreshed on package changes.
final installedAppsProvider =
    AsyncNotifierProvider<InstalledAppsNotifier, List<InstalledApp>>(
      InstalledAppsNotifier.new,
    );

/// The TV's own inputs (HDMI ports, tuner); empty on devices without any.
final tvInputsProvider = AsyncNotifierProvider<TvInputsNotifier, List<TvInput>>(
  TvInputsNotifier.new,
);

/// A list read from the device that is re-read whenever the device says it
/// changed.
abstract class _DeviceListNotifier<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> load(LauncherPlatform platform);
  Stream<void> changes(LauncherPlatform platform);

  int _generation = 0;

  @override
  Future<List<T>> build() {
    final platform = ref.watch(launcherPlatformProvider);
    // The subscription lives as long as the provider, so no change event is
    // missed while a refresh is in flight.
    final sub = changes(platform).listen((_) => _refresh(platform));
    ref.onDispose(sub.cancel);
    return load(platform);
  }

  Future<void> _refresh(LauncherPlatform platform) async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(() => load(platform));
    // Changes arrive in bursts; only the newest query may publish.
    if (ref.mounted && generation == _generation) state = next;
  }
}

class InstalledAppsNotifier extends _DeviceListNotifier<InstalledApp> {
  @override
  Future<List<InstalledApp>> load(LauncherPlatform platform) =>
      platform.listApps();

  @override
  Stream<void> changes(LauncherPlatform platform) => platform.appsChanged;
}

class TvInputsNotifier extends _DeviceListNotifier<TvInput> {
  @override
  Future<List<TvInput>> load(LauncherPlatform platform) =>
      platform.listInputs();

  @override
  Stream<void> changes(LauncherPlatform platform) => platform.inputsChanged;
}

/// Every card the device offers, in display order, hidden ones included.
/// This is what the config page edits.
final allCardsProvider = FutureProvider<List<LauncherCard>>((ref) async {
  final apps = await ref.watch(installedAppsProvider.future);
  final inputs = await ref.watch(tvInputsProvider.future);
  final config = await ref.watch(configProvider.future);
  final available = [
    for (final input in inputs)
      LauncherCard(
        id: LauncherCard.inputId(input.id),
        kind: CardKind.input,
        target: input.id,
        label: input.label,
        svg: inputArtworkSvg(input.kind, input.label),
      ),
    for (final app in apps)
      LauncherCard(
        id: LauncherCard.appId(app.packageName),
        kind: CardKind.app,
        target: app.packageName,
        label: app.label,
        iconPath: app.iconPath,
        wideIcon: app.isBanner,
      ),
  ];
  return arrangeCards(available, config, includeHidden: true);
});

/// The cards to show on the home screen, in order, with user config applied.
final cardsProvider = FutureProvider<List<LauncherCard>>((ref) async {
  final all = await ref.watch(allCardsProvider.future);
  final config = await ref.watch(configProvider.future);
  return [
    for (final card in all)
      if (!config.hidden.contains(card.id)) card,
  ];
});

/// Applies [config] to the cards the device offers: drops hidden ones (unless
/// [includeHidden]), swaps in custom icons, and sorts by the saved order.
/// Unlisted cards go last: inputs before apps, each alphabetically.
List<LauncherCard> arrangeCards(
  List<LauncherCard> available,
  LauncherConfig config, {
  bool includeHidden = false,
}) {
  final position = {for (final (i, id) in config.order.indexed) id: i};
  final cards = [
    for (final card in available)
      if (includeHidden || !config.hidden.contains(card.id))
        switch (config.iconOverrides[card.id]) {
          null => card,
          // Custom art is assumed to be drawn for the full card.
          final path => LauncherCard(
            id: card.id,
            kind: card.kind,
            target: card.target,
            label: card.label,
            iconPath: path,
            wideIcon: true,
          ),
        },
  ];
  cards.sort((a, b) {
    final pa = position[a.id], pb = position[b.id];
    if (pa != null && pb != null) return pa.compareTo(pb);
    if (pa != null) return -1;
    if (pb != null) return 1;
    if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return cards;
}

final cardActionsProvider = Provider<CardActions>(CardActions.new);

/// Things that can be done with a card; shared by the TV UI and web server.
class CardActions {
  CardActions(this._ref);

  final Ref _ref;

  Future<void> launch(LauncherCard card) => switch (card.kind) {
    CardKind.app => _ref.read(launcherPlatformProvider).launchApp(card.target),
    CardKind.input =>
      _ref.read(launcherPlatformProvider).switchToInput(card.target),
  };
}
