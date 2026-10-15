import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/updates/update_controller.dart';

/// Updates of the launcher itself. Where they come from is not an argument.
class UpdateOperationsManager implements OperationsManager {
  UpdateOperationsManager(this._ref);

  final Ref _ref;

  UpdateController get _updates => _ref.read(updateControllerProvider.notifier);

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'launcher://updates/check',
      label: 'Check for an update of the launcher',
      run: (run) => _updates.check(),
    ),
    Operation(
      name: 'launcher://updates/install',
      label: 'Install the latest update of the launcher',
      run: (run) => _updates.install(),
    ),
  ];
}
