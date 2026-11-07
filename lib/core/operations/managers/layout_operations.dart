import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// What is on a screen, named by `screen`.
class LayoutOperationsManager extends OperationsManager {
  LayoutOperationsManager(this._layout);

  final LayoutService _layout;

  @override
  String get area => 'launcher://layout';

  @override
  late final List<Operation> operations = [
    operation(
      'add',
      label: 'Add an entity to a screen',
      // `what` is an entity id; `to` a container on the screen, else the inbox.
      args: const {'screen': [], 'what': [], 'to': []},
      requiredArgs: const {'screen', 'what'},
      run: (run) => _layout.add(
        screen: run.required('screen'),
        what: run.required('what'),
        to: run.arg('to'),
      ),
    ),
    operation(
      'remove',
      label: 'Remove an entity from a screen',
      // `what` is an entity id; every instance handed it is removed.
      args: const {'screen': [], 'what': []},
      requiredArgs: const {'what'},
      run: (run) =>
          _layout.remove(what: run.required('what'), screen: run.arg('screen')),
    ),
  ];
}
