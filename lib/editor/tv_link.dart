import 'dart:convert';

import 'package:flutter_riverpod/misc.dart';
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
  launcherPlatformProvider.overrideWith((ref) {
    final platform = BrowserPlatform(ref.watch(tvApiProvider));
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

/// The device as a browser has it: the TV, at the other end of [TvApi]. What
/// the launcher here asks the device to do is done there, as if the press
/// had come from the TV's remote. What apps and inputs there are is not
/// asked of it: the TV sends its entities ready made.
class BrowserPlatform extends FakeLauncherPlatform {
  BrowserPlatform(this._api) : super(const [], const []);

  final TvApi _api;

  /// Takes [now] as what is playing on the TV.
  void hear(NowPlaying? now) {
    playing = now;
    notifyNowPlayingChanged();
  }

  // Here an entity's target is its id, which is what the TV knows it by.
  @override
  Future<void> launchApp(String packageName) =>
      _api.press('open', entity: packageName);

  @override
  Future<void> switchToInput(String inputId) =>
      _api.press('open', entity: inputId);

  @override
  Future<void> openAppInfo(String packageName) =>
      _api.press('info', entity: packageName);

  @override
  Future<void> uninstallApp(String packageName) =>
      _api.press('uninstall', entity: packageName);

  @override
  Future<bool> forceStopApp(String packageName) async =>
      (await _api.press('forceStop', entity: packageName))['done'] == true;

  @override
  Future<void> sendMediaCommand(MediaCommand command) =>
      _api.press('media', more: {'command': command.name});

  @override
  Future<bool> isHomeButtonEnabled() async =>
      (await _api.press('homeButton'))['enabled'] == true;

  @override
  Future<bool> canManageHomeButton() async =>
      (await _api.press('homeButton'))['canManage'] == true;

  @override
  Future<void> setHomeButtonEnabled(bool enabled) =>
      _api.press('homeButton', more: {'enabled': enabled});

  @override
  Future<void> openHomeButtonSettings() => _api.press('tvSettings');

  @override
  Future<SetupResult> runAutomaticSetup() async {
    final said = await _api.press('setup');
    return SetupResult(
      outcome: SetupOutcome.values.byName(said['outcome'] as String),
      detail: said['detail'] as String?,
    );
  }
}
