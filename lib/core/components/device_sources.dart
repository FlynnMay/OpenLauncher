import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What is playing, or null. Needs [Access.notifications].
final nowPlayingProvider =
    AsyncNotifierProvider<NowPlayingNotifier, NowPlaying?>(
      NowPlayingNotifier.new,
    );

class NowPlayingNotifier extends AsyncNotifier<NowPlaying?> {
  int _generation = 0;

  @override
  Future<NowPlaying?> build() {
    final platform = ref.watch(launcherPlatformProvider);
    final sub = platform.nowPlayingChanged.listen((_) async {
      final generation = ++_generation;
      final next = await AsyncValue.guard(platform.nowPlaying);
      // Only the newest of a burst of reloads publishes.
      if (ref.mounted && generation == _generation) state = next;
    });
    ref.onDispose(sub.cancel);
    return platform.nowPlaying();
  }
}

/// App widgets offered by installed apps.
final widgetProvidersProvider = FutureProvider<List<WidgetProvider>>((ref) {
  final platform = ref.watch(launcherPlatformProvider);
  // New apps can bring new widgets.
  final sub = platform.appsChanged.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return platform.listWidgetProviders();
});
