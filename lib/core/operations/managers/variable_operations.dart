import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// Runtime values of components' variables.
class VariableOperationsManager extends OperationsManager {
  VariableOperationsManager(this._variables);

  final VariableService _variables;

  @override
  String get area => 'launcher://variables';

  @override
  late final List<Operation> operations = [
    operation(
      'set',
      label: "Set a component's variable",
      // `of` is a node of the screen shown; none, the component that fired it.
      args: const {'var': [], 'value': [], 'of': []},
      requiredArgs: const {'var'},
      run: (run) => _variables.set(
        variable: run.required('var'),
        value: run.args['value'],
        of: run.arg('of'),
        component: run.component,
      ),
    ),
  ];
}
