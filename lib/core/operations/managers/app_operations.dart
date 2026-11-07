import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What can be done to an installed app, named by its `package`.
class AppOperationsManager implements OperationsManager {
  AppOperationsManager(this._platform);

  final LauncherPlatform _platform;

  static const _package = {'package': <String>[]};
  static const _needsPackage = {'package'};

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'os://apps/launch',
      label: 'Open an app',
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) async {
        await _platform.launchApp(run.required('package'));
        return null;
      },
    ),
    Operation(
      name: 'os://apps/info',
      label: "Open an app's info screen",
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) async {
        await _platform.openAppInfo(run.required('package'));
        return null;
      },
    ),
    Operation(
      name: 'os://apps/uninstall',
      label: 'Uninstall an app',
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) async {
        await _platform.uninstallApp(run.required('package'));
        return null;
      },
    ),
  ];
}
