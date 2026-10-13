import 'dart:async';

import 'package:flutter/services.dart';

import 'package:openlauncher/platform/launcher_platform.dart';

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

  /// What the user has allowed, and what they were sent to change.
  final access = {for (final access in Access.values) access: true};
  final accessChanged = <Access>[];
  int tvSettingsOpened = 0;

  @override
  Future<bool> hasAccess(Access access) async => this.access[access]!;

  /// As on a TV whose settings have no screen for it.
  bool noAccessScreen = false;

  @override
  Future<void> changeAccess(Access access) async {
    if (noAccessScreen) throw PlatformException(code: 'no-settings');
    accessChanged.add(access);
  }

  @override
  Future<void> openTvSettings() async => tvSettingsOpened++;

  /// The APKs handed over to install, and why the device installs none.
  final installed = <String>[];
  String installRefusal = 'There is no TV here.';

  @override
  Future<String> installUpdate(String path) async {
    installed.add(path);
    return installRefusal;
  }

  /// What was done to apps, e.g. `uninstall fake.plex`.
  final appActions = <String>[];

  @override
  Future<void> openAppInfo(String packageName) async =>
      appActions.add('info $packageName');

  @override
  Future<void> uninstallApp(String packageName) async =>
      appActions.add('uninstall $packageName');

  NowPlaying? playing;
  final mediaCommands = <MediaCommand>[];
  final _nowPlayingChanged = StreamController<void>.broadcast();
  final _notifications = StreamController<AppNotification>.broadcast();

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
