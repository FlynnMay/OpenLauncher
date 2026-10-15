import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// Runtime values of components' variables.
class VariableOperationsManager implements OperationsManager {
  VariableOperationsManager(this._ref);

  final Ref _ref;

  @override
  late final List<Operation> operations = [
    // Runtime only; not saved.
    Operation(
      name: 'launcher://variables/set',
      label: "Set a component's variable",
      args: const {'var': [], 'value': [], 'of': []},
      run: (run) async {
        // Defaults to the component that fired it.
        final component = run.arg('of') ?? run.component;
        final name = run.arg('var');
        if (component == null || name == null) return null;
        final value = switch (run.args['value']) {
          // Evaluated now, so a toggle can read its own value.
          final String text when text.contains('{{') => readTemplate(
            _ref.read,
            text,
            const {},
          ),
          final value => value,
        };
        _ref.read(runtimeVarsProvider.notifier).set(component, name, value);
        return null;
      },
    ),
  ];
}
