import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What can be done to an installed app, named by its `package`.
class AppOperationsManager extends OperationsManager {
  AppOperationsManager(this._platform);

  final LauncherPlatform _platform;

  static const _package = {'package': <String>[]};
  static const _needsPackage = {'package'};

  @override
  String get area => 'os://apps';

  @override
  late final List<Operation> operations = [
    operation(
      'launch',
      label: 'Open an app',
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) async {
        await _platform.launchApp(run.required('package'));
        return null;
      },
    ),
    operation(
      'info',
      label: "Open an app's info screen",
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) async {
        await _platform.openAppInfo(run.required('package'));
        return null;
      },
    ),
    operation(
      'uninstall',
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
