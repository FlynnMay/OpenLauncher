import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/input_artwork.dart';
import 'package:openlauncher/core/cards/launcher_card.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

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

/// Every card the device offers, removed ones included, with the user's
/// pictures and names applied. Inputs come before apps, each alphabetically. Where
/// they are shown is up to the layout.
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
    LauncherCard.settings,
  ];
  return arrangeCards(available, config);
});

/// Swaps in the user's pictures and names and sorts the cards the device
/// offers: inputs before apps, each alphabetically.
List<LauncherCard> arrangeCards(
  List<LauncherCard> available,
  LauncherConfig config,
) {
  final pictured = {
    for (final card in available)
      card.id: switch (config.iconOverrides[card.id]) {
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
  };
  final cards = [
    for (var card in pictured.values)
      () {
        // The other card's picture as it would show by itself: a card that
        // borrows in turn is not followed, so there are no chains or loops.
        // A card whose source is gone keeps its own until it is back.
        if (pictured[config.iconSources[card.id]] case final source?) {
          card = card.withPictureOf(source);
        }
        if (config.names[card.id] case final name?) {
          card = card.withLabel(name);
        }
        return card;
      }(),
  ];
  cards.sort((a, b) {
    if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return cards;
}

final cardActionsProvider = Provider<CardActions>(CardActions.new);

/// Opening a card; shared by the TV UI and web server. What else is done
/// with a card is an `ActionKind`.
class CardActions {
  CardActions(this._ref);

  final Ref _ref;

  LauncherPlatform get _platform => _ref.read(launcherPlatformProvider);

  Future<void> launch(LauncherCard card) => switch (card.kind) {
    CardKind.app => _platform.launchApp(card.target),
    CardKind.input => _platform.switchToInput(card.target),
    // The launcher's own screens are opened by the UI showing the card.
    CardKind.action => throw UnsupportedError('Not something to launch'),
  };
}
