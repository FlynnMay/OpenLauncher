import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

final installedAppsProvider =
    AsyncNotifierProvider<InstalledAppsNotifier, List<InstalledApp>>(
      InstalledAppsNotifier.new,
    );

/// The TV's inputs (HDMI ports, tuner).
final tvInputsProvider = AsyncNotifierProvider<TvInputsNotifier, List<TvInput>>(
  TvInputsNotifier.new,
);

/// A device list that reloads when the device reports a change.
abstract class _DeviceListNotifier<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> load(LauncherPlatform platform);
  Stream<void> changes(LauncherPlatform platform);

  int _generation = 0;

  @override
  Future<List<T>> build() {
    final platform = ref.watch(launcherPlatformProvider);
    // Subscribed for the provider's lifetime so no change is missed.
    final sub = changes(platform).listen((_) => _refresh(platform));
    ref.onDispose(sub.cancel);
    return load(platform);
  }

  Future<void> _refresh(LauncherPlatform platform) async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(() => load(platform));
    // Only the newest of a burst of reloads publishes.
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

/// Needs [Access.notifications].
final nowPlayingProvider =
    AsyncNotifierProvider<NowPlayingNotifier, NowPlaying?>(
      NowPlayingNotifier.new,
    );

class NowPlayingNotifier extends AsyncNotifier<NowPlaying?> {
  int _generation = 0;

  @override
  Future<NowPlaying?> build() {
    final platform = ref.watch(launcherPlatformProvider);
    final subscription = platform.nowPlayingChanged.listen((_) async {
      final generation = ++_generation;
      final next = await AsyncValue.guard(platform.nowPlaying);
      // Only the newest of a burst of reloads publishes.
      if (ref.mounted && generation == _generation) state = next;
    });
    ref.onDispose(subscription.cancel);
    return platform.nowPlaying();
  }
}

final widgetProvidersProvider = FutureProvider<List<WidgetProvider>>((ref) {
  final platform = ref.watch(launcherPlatformProvider);
  // New apps can bring new widgets.
  final subscription = platform.appsChanged.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return platform.listWidgetProviders();
});
