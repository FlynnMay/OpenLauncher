import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What is playing on the TV right now, or null. Needs notification access.
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
      // Changes arrive in bursts; only the newest query may publish.
      if (ref.mounted && generation == _generation) state = next;
    });
    ref.onDispose(sub.cancel);
    return platform.nowPlaying();
  }
}

/// Whether the launcher may see notifications and media sessions.
final notificationAccessProvider = FutureProvider<bool>(
  (ref) => ref.watch(launcherPlatformProvider).isNotificationAccessEnabled(),
);

/// Widgets installed apps offer; empty where the device has none.
final widgetProvidersProvider = FutureProvider<List<WidgetProvider>>((ref) {
  final platform = ref.watch(launcherPlatformProvider);
  // New apps can bring new widgets.
  final sub = platform.appsChanged.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return platform.listWidgetProviders();
});

/// Whether the remote's Home button opens this launcher.
final homeButtonEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(launcherPlatformProvider).isHomeButtonEnabled(),
);

/// Whether the app may switch the Home button on and off itself, which it can
/// once automatic setup has run.
final canManageHomeButtonProvider = FutureProvider<bool>(
  (ref) => ref.watch(launcherPlatformProvider).canManageHomeButton(),
);
