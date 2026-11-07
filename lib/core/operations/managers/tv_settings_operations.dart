import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// The TV's own settings.
class TvSettingsOperationsManager extends OperationsManager {
  TvSettingsOperationsManager(this._platform);

  final LauncherPlatform _platform;

  @override
  String get area => 'os://settings';

  @override
  late final List<Operation> operations = [
    operation(
      'open',
      label: "Open the TV's settings",
      run: (run) async {
        await _platform.openTvSettings();
        return null;
      },
    ),
  ];
}
