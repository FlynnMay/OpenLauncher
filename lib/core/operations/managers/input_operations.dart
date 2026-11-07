import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What can be done to a TV input.
class InputOperationsManager implements OperationsManager {
  InputOperationsManager(this._platform);

  final LauncherPlatform _platform;

  @override
  late final List<Operation> operations = [
    Operation(
      address: 'os://inputs/switch',
      label: 'Switch to a TV input',
      args: const {'input': []},
      requiredArgs: const {'input'},
      run: (run) async {
        await _platform.switchToInput(run.required('input'));
        return null;
      },
    ),
  ];
}
