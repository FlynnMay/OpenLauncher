import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// What can be done to an installed app, named by its `package`.
class AppOperationsManager extends OperationsManager {
  AppOperationsManager(this._apps);

  final AppService _apps;

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
      run: (run) => _apps.launch(run.required('package')),
    ),
    operation(
      'info',
      label: "Open an app's info screen",
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) => _apps.showInfo(run.required('package')),
    ),
    operation(
      'uninstall',
      label: 'Uninstall an app',
      args: _package,
      requiredArgs: _needsPackage,
      run: (run) => _apps.uninstall(run.required('package')),
    ),
  ];
}
