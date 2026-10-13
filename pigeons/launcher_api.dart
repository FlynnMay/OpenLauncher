// Pigeon definition of the Dart <-> Android bridge.
// Regenerate with: dart run pigeon --input pigeons/launcher_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/launcher_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/maypoint/openlauncher/LauncherApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.maypoint.openlauncher'),
    dartPackageName: 'openlauncher',
  ),
)
class InstalledApp {
  InstalledApp({
    required this.packageName,
    required this.label,
    required this.isBanner,
    this.iconPath,
  });

  String packageName;
  String label;

  /// Absolute path of a cached PNG, or null if the app has no drawable.
  String? iconPath;

  /// True when [iconPath] is a 16:9 TV banner rather than a square icon.
  bool isBanner;
}

/// What is plugged into an input; decides which picture its card gets.
enum TvInputKind {
  hdmi,
  tuner,

  /// Analogue video: composite, component, S-Video, SCART.
  analog,
  other,
}

/// A hardware input of the TV (HDMI port, tuner, ...).
class TvInput {
  TvInput({required this.id, required this.label, required this.kind});

  /// The TV Input Framework id, e.g. `com.vendor.tvinput/.Service/HW15`.
  String id;
  String label;
  TvInputKind kind;
}

/// What the user allows the launcher in the TV's own settings.
enum Access {
  /// The accessibility service that catches the Home button.
  homeButton,

  /// Other apps' notifications and media sessions (toasts, now playing).
  notifications,
}

/// What an app is playing, as reported by its media session.
class NowPlaying {
  NowPlaying({
    required this.packageName,
    required this.appLabel,
    required this.playing,
    this.title,
    this.artist,
    this.artPath,
  });

  String packageName;
  String appLabel;
  String? title;
  String? artist;

  /// Absolute path of the cover art as a cached PNG, if the app gives any.
  String? artPath;
  bool playing;
}

enum MediaCommand { playPause, next, previous }

/// A notification another app has just posted.
class AppNotification {
  AppNotification({
    required this.packageName,
    required this.appLabel,
    this.title,
    this.text,
  });

  String packageName;
  String appLabel;
  String? title;
  String? text;
}

/// A widget an installed app offers.
class WidgetProvider {
  WidgetProvider({
    required this.id,
    required this.label,
    required this.appLabel,
  });

  /// The provider's component name, e.g. `com.example/.ClockWidget`.
  String id;
  String label;
  String appLabel;
}

@HostApi()
abstract class LauncherHostApi {
  @async
  List<InstalledApp> listApps();

  void launchApp(String packageName);

  /// Empty on devices without hardware inputs (streaming boxes, dongles).
  @async
  List<TvInput> listInputs();

  void switchToInput(String inputId);

  bool hasAccess(Access access);

  /// Opens the TV's screen where [access] is allowed or withdrawn. The Home
  /// button is switched at once instead where the TV lets the app do that.
  void changeAccess(Access access);

  void openTvSettings();

  /// Opens the TV's own details screen for an app.
  void openAppInfo(String packageName);

  /// Asks the TV to uninstall an app; the TV confirms with the user.
  void uninstallApp(String packageName);

  /// Has the TV install the downloaded APK at [path] over this app; the TV
  /// may ask the user first. The install ends this process, so an answer is
  /// only ever why it did not happen.
  @async
  String installUpdate(String path);

  /// Null when nothing is playing or access has not been granted.
  @async
  NowPlaying? getNowPlaying();

  void sendMediaCommand(MediaCommand command);

  /// Empty on devices that do not support app widgets.
  List<WidgetProvider> listWidgetProviders();

  /// Makes sure the layout item [itemId] has a widget from [provider] and
  /// returns the id to show it with, or null if the TV or the user does not
  /// allow it. The TV may ask the user first.
  @async
  int? bindWidget(String itemId, String provider);

  /// Frees the widgets of layout items that are not in [itemIds] any more.
  void pruneWidgets(List<String> itemIds);
}

@FlutterApi()
abstract class LauncherFlutterApi {
  /// A package was installed, removed or updated.
  void onAppsChanged();

  /// An input was added, removed or renamed.
  void onInputsChanged();

  /// What [LauncherHostApi.getNowPlaying] returns has changed.
  void onNowPlayingChanged();

  void onNotification(AppNotification notification);
}
