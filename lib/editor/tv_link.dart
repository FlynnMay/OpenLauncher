import 'dart:convert';

import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_server.dart';

/// What makes the launcher run in a browser as it runs on the TV: its
/// config, cards and wallpaper come from the TV over the network instead of
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
  allCardsProvider.overrideWith(
    (ref) async => (await ref.watch(tvStateProvider.future)).cards,
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
  launcherPlatformProvider.overrideWithValue(BrowserPlatform()),
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

  static String _options(LauncherConfig config) => jsonEncode([
    [for (final action in config.contextMenu) action.name],
    config.toasts,
  ]);

  @override
  Future<void> save(LauncherConfig config) async {
    final known = _known ?? await load();
    _known = config;
    if (jsonEncode(config.layout) != jsonEncode(known.layout)) {
      await _api.setLayout(config.layout);
    }
    if (_options(config) != _options(known)) await _api.setOptions(config);
  }
}

/// Said when the page is asked to do something only the TV can do.
class NotFromHere implements Exception {
  const NotFromHere();

  @override
  String toString() => 'this page cannot do that on the TV yet';
}

/// The device as a browser has it: there is none. What the launcher asks of
/// the device is answered with nothing, and what it asks the device to do
/// is refused, until the TV offers a way to pass such things on.
class BrowserPlatform extends FakeLauncherPlatform {
  BrowserPlatform() : super(const [], const []);

  @override
  Future<void> launchApp(String packageName) => throw const NotFromHere();

  @override
  Future<void> switchToInput(String inputId) => throw const NotFromHere();

  @override
  Future<void> openAppInfo(String packageName) => throw const NotFromHere();

  @override
  Future<void> uninstallApp(String packageName) => throw const NotFromHere();

  @override
  Future<bool> forceStopApp(String packageName) => throw const NotFromHere();

  @override
  Future<void> openHomeButtonSettings() => throw const NotFromHere();

  @override
  Future<void> setHomeButtonEnabled(bool enabled) => throw const NotFromHere();

  @override
  Future<SetupResult> runAutomaticSetup() => throw const NotFromHere();
}
