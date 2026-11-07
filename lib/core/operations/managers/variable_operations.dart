import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/screens/screens.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// Runtime values of components' variables.
class VariableOperationsManager extends OperationsManager {
  VariableOperationsManager(this._ref);

  final Ref _ref;

  @override
  String get area => 'launcher://variables';

  @override
  late final List<Operation> operations = [
    // Runtime only; not saved.
    operation(
      'set',
      label: "Set a component's variable",
      args: const {'var': [], 'value': [], 'of': []},
      requiredArgs: const {'var'},
      run: (run) async {
        // Defaults to the component that fired it.
        final component = switch (run.arg('of')) {
          // A node of the screen shown, by the id it is named with there.
          final of? => _ref.read(currentScreenProvider)?.find(of)?.id ?? of,
          null => run.component,
        };
        final name = run.required('var');
        if (component == null) return null;
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
