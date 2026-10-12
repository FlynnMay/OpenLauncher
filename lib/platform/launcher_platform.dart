import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/platform/fake_launcher_platform.dart';
import 'package:openlauncher/platform/launcher_api.g.dart';

export 'fake_launcher_platform.dart';
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

/// What the launcher needs from the device. Faked on desktop and in tests.
abstract class LauncherPlatform {
  Future<List<InstalledApp>> listApps();
  Future<void> launchApp(String packageName);

  /// Fires when a package is installed, removed or updated.
  Stream<void> get appsChanged;

  Future<List<TvInput>> listInputs();
  Future<void> switchToInput(String inputId);

  /// Fires when an input is added, removed or renamed.
  Stream<void> get inputsChanged;

  /// Whether the remote's Home button opens this launcher.
  Future<bool> isHomeButtonEnabled();
  Future<void> openHomeButtonSettings();

  /// True once [runAutomaticSetup] has succeeded.
  Future<bool> canManageHomeButton();
  Future<void> setHomeButtonEnabled(bool enabled);

  /// Grants the app's permissions through the TV's ADB service and enables
  /// the Home button. The TV asks the user to allow it.
  Future<SetupResult> runAutomaticSetup();

  /// Installs the APK at [path] over the launcher, which restarts it. Only
  /// returns if it could not: [SetupResult.detail] says why.
  Future<SetupResult> installUpdate(String path);

  Future<void> openAppInfo(String packageName);

  /// The device confirms with the user.
  Future<void> uninstallApp(String packageName);

  /// False if the device refused.
  Future<bool> forceStopApp(String packageName);

  /// Granted by [runAutomaticSetup].
  Future<bool> isNotificationAccessEnabled();

  Future<NowPlaying?> nowPlaying();
  Future<void> sendMediaCommand(MediaCommand command);

  Stream<void> get nowPlayingChanged;

  /// Notifications posted while the launcher runs.
  Stream<AppNotification> get notifications;

  Future<List<WidgetProvider>> listWidgetProviders();

  /// The native widget id for a component, or null if refused.
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
  Future<SetupResult> installUpdate(String path) => _host.installUpdate(path);

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
