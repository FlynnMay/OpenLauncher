import 'dart:convert';

import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

/// Provider overrides that run the launcher in a browser: config, entities
/// and wallpapers come from the TV, and config changes go back to it.
final List<Override> tvOverrides = [
  configStoreProvider.overrideWith(
    // A new store per state, so the config is re-read.
    (ref) => TvConfigStore(
      ref.watch(tvApiProvider),
      ref.watch(tvStateProvider.future),
    ),
  ),
  entitiesProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).entities,
  ),
  // Rotation is computed locally, as on the TV.
  wallpapersProvider.overrideWith(
    (ref) => [
      for (final one
          in ref.watch(tvStateProvider).value?.wallpapers ?? const [])
        one.wallpaper,
    ],
  ),
  wallpaperEveryProvider.overrideWith(
    (ref) => ref.watch(tvStateProvider).value?.wallpaperEvery ?? 0,
  ),
  actionRunnerProvider.overrideWith(
    (ref) => TvActionRunner(ref, ref.watch(tvApiProvider)),
  ),
  homeButtonEnabledProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).homeButton,
  ),
  canManageHomeButtonProvider.overrideWith(
    (ref) async =>
        (await ref.watch(tvStateProvider.future)).canManageHomeButton,
  ),
  launcherPlatformProvider.overrideWith((ref) {
    final platform = BrowserPlatform();
    ref.listen(tvStateProvider, (_, next) {
      if (next.value case final state?) platform.hear(state.nowPlaying);
    }, fireImmediately: true);
    return platform;
  }),
  // Browsers cannot make cross-site requests; the TV can.
  sourceFetcherProvider.overrideWith((ref) {
    final api = ref.watch(tvApiProvider);
    return (source) => api.sourceValue(source.id);
  }),
  // The page is the config server's guest; it does not run one.
  configServerProvider.overrideWith((ref) async => null),
];

/// The TV's config. Saving sends what changed.
class TvConfigStore implements ConfigStore {
  TvConfigStore(this._api, this._state);

  final TvApi _api;
  final Future<TvState> _state;

  /// What the TV has: last received or last sent.
  LauncherConfig? _known;

  @override
  Future<LauncherConfig> load() async => _known = (await _state).config;

  @override
  Future<void> save(LauncherConfig config) async {
    final known = _known ?? await load();
    _known = config;
    if (jsonEncode(config.layout) != jsonEncode(known.layout)) {
      await _api.setLayout(config.layout);
    }
    // Compared key by key.
    final was = known.open, now = config.open;
    final changed = {
      for (final key in LauncherConfig.openKeys)
        if (jsonEncode(now[key]) != jsonEncode(was[key])) key: now[key],
    };
    if (changed.isNotEmpty) await _api.setConfig(changed);
  }
}

/// The browser's "device": nothing of its own. Entities arrive from the TV
/// and device actions are sent to it.
class BrowserPlatform extends FakeLauncherPlatform {
  BrowserPlatform() : super(const [], const []);

  void hear(NowPlaying? now) {
    playing = now;
    notifyNowPlayingChanged();
  }
}

/// Sends device actions to the TV and runs the rest locally.
class TvActionRunner extends ActionRunner {
  TvActionRunner(super.ref, this._api);

  final TvApi _api;

  @override
  Future<String?> carryOut(ActionRegistry action, ActionRun run) =>
      action.onDevice ? _api.act(run.act) : super.carryOut(action, run);
}
