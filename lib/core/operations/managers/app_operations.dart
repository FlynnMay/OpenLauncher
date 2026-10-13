import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What can be done to an installed app, named by its `package`.
class AppOperationsManager implements OperationsManager {
  AppOperationsManager(this._platform);

  final LauncherPlatform _platform;

  static const _package = {'package': <String>[]};

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'launchApp',
      label: 'Open an app',
      args: _package,
      onDevice: true,
      run: (run) async {
        await _platform.launchApp(_packageOf(run));
        return null;
      },
    ),
    Operation(
      name: 'openAppInfo',
      label: "Open an app's info screen",
      args: _package,
      onDevice: true,
      run: (run) async {
        await _platform.openAppInfo(_packageOf(run));
        return null;
      },
    ),
    Operation(
      name: 'uninstallApp',
      label: 'Uninstall an app',
      args: _package,
      onDevice: true,
      run: (run) async {
        await _platform.uninstallApp(_packageOf(run));
        return null;
      },
    ),
  ];

  String _packageOf(OperationRun run) => switch (run.arg('package')) {
    final String package when package.isNotEmpty => package,
    _ => throw const FormatException('No package was given'),
  };
}
