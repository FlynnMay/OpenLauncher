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

/// What makes the launcher run in a browser as it runs on the TV: its
/// config, entities and wallpaper come from the TV over the network instead of
/// from the device, and changes to the config go back the same way. Nothing
/// above these providers knows the difference.
final List<Override> tvOverrides = [
  configStoreProvider.overrideWith(
    // A new one for each state the TV sends, so the config is read again.
    (ref) => TvConfigStore(
      ref.watch(tvApiProvider),
      ref.watch(tvStateProvider.future),
    ),
  ),
  entitiesProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).entities,
  ),
  // Which of them shows, and when the next takes its turn, is worked out
  // here as it is on the TV.
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
    // What plays comes with the rest of what the TV sends.
    ref.listen(tvStateProvider, (_, next) {
      if (next.value case final state?) platform.hear(state.nowPlaying);
    }, fireImmediately: true);
    return platform;
  }),
  // A browser may not ask other sites for what they have; the TV may.
  sourceFetcherProvider.overrideWith((ref) {
    final api = ref.watch(tvApiProvider);
    return (source) => api.sourceValue(source.id);
  }),
  // The page is the config server's guest; it does not run one.
  configServerProvider.overrideWith((ref) async => null),
];

/// The config as the TV has it. Saving sends the TV whatever changed.
class TvConfigStore implements ConfigStore {
  TvConfigStore(this._api, this._state);

  final TvApi _api;
  final Future<TvState> _state;

  /// What the TV is known to have: what it sent, or what it was last sent.
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
    // Whatever plain settings there are, without knowing any by name.
    final was = known.open, now = config.open;
    final changed = {
      for (final key in LauncherConfig.openKeys)
        if (jsonEncode(now[key]) != jsonEncode(was[key])) key: now[key],
    };
    if (changed.isNotEmpty) await _api.setConfig(changed);
  }
}

/// The device as a browser has it: nothing of its own. What apps and
/// inputs there are is not asked of it, since the TV sends its entities
/// ready made, and what is to be done on the TV goes there as an action.
class BrowserPlatform extends FakeLauncherPlatform {
  BrowserPlatform() : super(const [], const []);

  /// Takes [now] as what is playing on the TV.
  void hear(NowPlaying? now) {
    playing = now;
    notifyNowPlayingChanged();
  }
}

/// Carries actions out for the launcher in a browser: what the TV itself
/// does is sent to it, as if set off there, and the rest is done here.
class TvActionRunner extends ActionRunner {
  TvActionRunner(super.ref, this._api);

  final TvApi _api;

  @override
  Future<String?> carryOut(ActionKind kind, ActionRun run) => kind.onDevice
      ? _api.act(
          Act(run.act.name, {
            ...run.act.args,
            // The TV is told what it is done to, having no press to go by.
            entityArg: ?run.entity?.id,
          }),
        )
      : super.carryOut(kind, run);
}
