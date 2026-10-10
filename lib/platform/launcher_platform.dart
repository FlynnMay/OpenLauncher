import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/launcher_api.g.dart';

export 'launcher_api.g.dart'
    show
        AppNotification,
        InstalledApp,
        MediaCommand,
        NowPlaying,
        SetupOutcome,
        SetupResult,
        TvInput,
        TvInputKind,
        WidgetProvider;

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

  Future<void> openAppInfo(String packageName);

  /// Asks the device to uninstall an app; the device confirms with the user.
  Future<void> uninstallApp(String packageName);

  /// False when the device would not let the launcher stop the app.
  Future<bool> forceStopApp(String packageName);

  /// Whether the launcher may see other apps' notifications and what they
  /// are playing; granted by [runAutomaticSetup].
  Future<bool> isNotificationAccessEnabled();

  Future<NowPlaying?> nowPlaying();
  Future<void> sendMediaCommand(MediaCommand command);

  /// Fires when what [nowPlaying] returns has changed.
  Stream<void> get nowPlayingChanged;

  /// Notifications other apps post while the launcher is running.
  Stream<AppNotification> get notifications;

  /// Widgets offered by installed apps; empty where unsupported.
  Future<List<WidgetProvider>> listWidgetProviders();

  /// The native widget id for a layout item, or null if the device refuses.
  Future<int?> bindWidget(String itemId, String provider);
  Future<void> pruneWidgets(List<String> itemIds);
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
  final _nowPlayingChanged = StreamController<void>.broadcast();
  final _notifications = StreamController<AppNotification>.broadcast();

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

  @override
  Future<void> openAppInfo(String packageName) =>
      _host.openAppInfo(packageName);

  @override
  Future<void> uninstallApp(String packageName) =>
      _host.uninstallApp(packageName);

  @override
  Future<bool> forceStopApp(String packageName) =>
      _host.forceStopApp(packageName);

  @override
  Future<bool> isNotificationAccessEnabled() =>
      _host.isNotificationAccessEnabled();

  @override
  Future<NowPlaying?> nowPlaying() => _host.getNowPlaying();

  @override
  Future<void> sendMediaCommand(MediaCommand command) =>
      _host.sendMediaCommand(command);

  @override
  Stream<void> get nowPlayingChanged => _nowPlayingChanged.stream;

  @override
  void onNowPlayingChanged() => _nowPlayingChanged.add(null);

  @override
  Stream<AppNotification> get notifications => _notifications.stream;

  @override
  void onNotification(AppNotification notification) =>
      _notifications.add(notification);

  @override
  Future<List<WidgetProvider>> listWidgetProviders() =>
      _host.listWidgetProviders();

  @override
  Future<int?> bindWidget(String itemId, String provider) =>
      _host.bindWidget(itemId, provider);

  @override
  Future<void> pruneWidgets(List<String> itemIds) =>
      _host.pruneWidgets(itemIds);

  void dispose() {
    LauncherFlutterApi.setUp(null);
    _appsChanged.close();
    _inputsChanged.close();
    _nowPlayingChanged.close();
    _notifications.close();
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

  /// What was done to apps, e.g. `uninstall fake.plex`.
  final appActions = <String>[];
  bool canForceStop = true;

  @override
  Future<void> openAppInfo(String packageName) async =>
      appActions.add('info $packageName');

  @override
  Future<void> uninstallApp(String packageName) async =>
      appActions.add('uninstall $packageName');

  @override
  Future<bool> forceStopApp(String packageName) async {
    if (canForceStop) appActions.add('stop $packageName');
    return canForceStop;
  }

  bool notificationAccess = true;
  NowPlaying? playing;
  final mediaCommands = <MediaCommand>[];
  final _nowPlayingChanged = StreamController<void>.broadcast();
  final _notifications = StreamController<AppNotification>.broadcast();

  @override
  Future<bool> isNotificationAccessEnabled() async => notificationAccess;

  @override
  Future<NowPlaying?> nowPlaying() async => playing;

  @override
  Future<void> sendMediaCommand(MediaCommand command) async =>
      mediaCommands.add(command);

  @override
  Stream<void> get nowPlayingChanged => _nowPlayingChanged.stream;

  void notifyNowPlayingChanged() => _nowPlayingChanged.add(null);

  @override
  Stream<AppNotification> get notifications => _notifications.stream;

  void notify(AppNotification notification) => _notifications.add(notification);

  List<WidgetProvider> widgetProviders = [];

  @override
  Future<List<WidgetProvider>> listWidgetProviders() async => widgetProviders;

  @override
  Future<int?> bindWidget(String itemId, String provider) async => null;

  @override
  Future<void> pruneWidgets(List<String> itemIds) async {}
}
