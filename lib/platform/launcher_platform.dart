import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'launcher_api.g.dart';

export 'launcher_api.g.dart'
    show InstalledApp, SetupOutcome, SetupResult, TvInput, TvInputKind;

/// What the launcher needs from the device. Everything above this layer is
/// platform-independent, so it runs on desktop and in tests with a fake.
abstract class LauncherPlatform {
  Future<List<InstalledApp>> listApps();
  Future<void> launchApp(String packageName);

  /// Fires when a package is installed, removed or updated.
  Stream<void> get appsChanged;

  /// The TV's own inputs; empty on devices that have none.
  Future<List<TvInput>> listInputs();
  Future<void> switchToInput(String inputId);

  /// Fires when an input is added, removed or renamed.
  Stream<void> get inputsChanged;

  /// Whether the remote's Home button opens this launcher. On Google TV that
  /// needs a service the user switches on in the TV's settings.
  Future<bool> isHomeButtonEnabled();
  Future<void> openHomeButtonSettings();

  /// Whether the app can switch the Home button itself; true once
  /// [runAutomaticSetup] has succeeded.
  Future<bool> canManageHomeButton();
  Future<void> setHomeButtonEnabled(bool enabled);

  /// Grants the app what it needs through the TV's own ADB service and
  /// switches the Home button on. The TV asks the user to allow it.
  Future<SetupResult> runAutomaticSetup();
}

final launcherPlatformProvider = Provider<LauncherPlatform>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final platform = AndroidLauncherPlatform();
    ref.onDispose(platform.dispose);
    return platform;
  }
  return FakeLauncherPlatform();
});

class AndroidLauncherPlatform implements LauncherPlatform, LauncherFlutterApi {
  AndroidLauncherPlatform() {
    LauncherFlutterApi.setUp(this);
  }

  final _host = LauncherHostApi();
  final _appsChanged = StreamController<void>.broadcast();
  final _inputsChanged = StreamController<void>.broadcast();

  @override
  Future<List<InstalledApp>> listApps() => _host.listApps();

  @override
  Future<void> launchApp(String packageName) => _host.launchApp(packageName);

  @override
  Stream<void> get appsChanged => _appsChanged.stream;

  @override
  void onAppsChanged() => _appsChanged.add(null);

  @override
  Future<List<TvInput>> listInputs() => _host.listInputs();

  @override
  Future<void> switchToInput(String inputId) => _host.switchToInput(inputId);

  @override
  Stream<void> get inputsChanged => _inputsChanged.stream;

  @override
  void onInputsChanged() => _inputsChanged.add(null);

  @override
  Future<bool> isHomeButtonEnabled() => _host.isHomeButtonEnabled();

  @override
  Future<void> openHomeButtonSettings() => _host.openHomeButtonSettings();

  @override
  Future<bool> canManageHomeButton() => _host.canManageHomeButton();

  @override
  Future<void> setHomeButtonEnabled(bool enabled) =>
      _host.setHomeButtonEnabled(enabled);

  @override
  Future<SetupResult> runAutomaticSetup() => _host.runAutomaticSetup();

  void dispose() {
    LauncherFlutterApi.setUp(null);
    _appsChanged.close();
    _inputsChanged.close();
  }
}

/// Stand-in used off-device (desktop runs, widget tests).
class FakeLauncherPlatform implements LauncherPlatform {
  FakeLauncherPlatform([List<InstalledApp>? apps, List<TvInput>? inputs])
    : inputs =
          inputs ??
          [
            TvInput(id: 'fake/HW1', label: 'HDMI 1', kind: TvInputKind.hdmi),
            TvInput(id: 'fake/HW2', label: 'HDMI 2', kind: TvInputKind.hdmi),
            TvInput(id: 'fake/HW3', label: 'TV', kind: TvInputKind.tuner),
          ],
      apps =
          apps ??
          [
            for (final name in const [
              'YouTube',
              'Netflix',
              'Plex',
              'Spotify',
              'Jellyfin',
              'Settings',
              'Kodi',
              'Twitch',
            ])
              InstalledApp(
                packageName: 'fake.${name.toLowerCase()}',
                label: name,
                isBanner: false,
              ),
          ];

  List<InstalledApp> apps;
  List<TvInput> inputs;

  /// Package names and input ids, in the order they were opened.
  final launched = <String>[];
  final _appsChanged = StreamController<void>.broadcast();
  final _inputsChanged = StreamController<void>.broadcast();

  @override
  Future<List<InstalledApp>> listApps() async => apps;

  @override
  Future<void> launchApp(String packageName) async => launched.add(packageName);

  @override
  Stream<void> get appsChanged => _appsChanged.stream;

  void notifyAppsChanged() => _appsChanged.add(null);

  @override
  Future<List<TvInput>> listInputs() async => inputs;

  @override
  Future<void> switchToInput(String inputId) async => launched.add(inputId);

  @override
  Stream<void> get inputsChanged => _inputsChanged.stream;

  void notifyInputsChanged() => _inputsChanged.add(null);

  bool homeButtonEnabled = true;
  int settingsOpened = 0;

  @override
  Future<bool> isHomeButtonEnabled() async => homeButtonEnabled;

  @override
  Future<void> openHomeButtonSettings() async => settingsOpened++;

  bool canManage = false;
  SetupOutcome setupOutcome = SetupOutcome.done;

  @override
  Future<bool> canManageHomeButton() async => canManage;

  @override
  Future<void> setHomeButtonEnabled(bool enabled) async =>
      homeButtonEnabled = enabled;

  @override
  Future<SetupResult> runAutomaticSetup() async {
    if (setupOutcome == SetupOutcome.done) {
      canManage = true;
      homeButtonEnabled = true;
    }
    return SetupResult(outcome: setupOutcome);
  }
}
