import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// What the TV allows the launcher.
class AccessOperationsManager extends OperationsManager {
  AccessOperationsManager(this._access);

  final AccessService _access;

  @override
  String get area => 'os://access';

  @override
  late final List<Operation> operations = [
    operation(
      'change',
      label: "Allow or withdraw a permission in the TV's settings",
      args: {
        'access': [for (final access in Access.values) access.name],
      },
      requiredArgs: const {'access'},
      run: (run) =>
          _access.change(Access.values.byName(run.required('access'))),
    ),
  ];
}
