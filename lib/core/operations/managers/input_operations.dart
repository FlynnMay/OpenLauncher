import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// What can be done to a TV input.
class InputOperationsManager extends OperationsManager {
  InputOperationsManager(this._inputs);

  final InputService _inputs;

  @override
  String get area => 'os://inputs';

  @override
  late final List<Operation> operations = [
    operation(
      'switch',
      label: 'Switch to a TV input',
      args: const {'input': []},
      requiredArgs: const {'input'},
      run: (run) => _inputs.switchTo(run.required('input')),
    ),
  ];
}
