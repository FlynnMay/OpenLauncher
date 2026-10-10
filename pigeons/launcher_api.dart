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

enum SetupOutcome {
  done,

  /// Nothing is listening for ADB on the TV: debugging is switched off.
  adbUnavailable,

  /// The "Allow USB debugging?" prompt was not accepted.
  notAuthorised,
  failed,
}

class SetupResult {
  SetupResult({required this.outcome, this.detail});

  SetupOutcome outcome;

  /// Technical detail for [SetupOutcome.failed].
  String? detail;
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

  /// Whether the Home button service is switched on in the TV's settings.
  bool isHomeButtonEnabled();

  /// Opens the settings screen where the Home button service is switched on.
  void openHomeButtonSettings();

  /// Whether the app may switch the Home button service on and off itself.
  /// True once [runAutomaticSetup] has succeeded.
  bool canManageHomeButton();

  void setHomeButtonEnabled(bool enabled);

  /// Grants this app what it needs through the TV's own ADB service, then
  /// switches the Home button service on.
  @async
  SetupResult runAutomaticSetup();
}

@FlutterApi()
abstract class LauncherFlutterApi {
  /// A package was installed, removed or updated.
  void onAppsChanged();

  /// An input was added, removed or renamed.
  void onInputsChanged();
}
