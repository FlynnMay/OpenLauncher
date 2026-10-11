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
      name: 'switchInput',
      label: 'Switch to a TV input',
      args: const {'input': []},
      onDevice: true,
      run: (run) async {
        final input = run.arg('input');
        if (input == null) throw const FormatException('No input was given');
        await _platform.switchToInput(input);
        return null;
      },
    ),
  ];
}
