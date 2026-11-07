import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// Which screen is shown, and the screens there are. Where a screen is named
/// by `id`, none means the one shown.
class ScreenOperationsManager extends OperationsManager {
  ScreenOperationsManager(this._screens);

  final ScreenService _screens;

  @override
  String get area => 'launcher://screen';

  @override
  late final List<Operation> operations = [
    operation(
      'open',
      label: 'Show a screen',
      args: const {'id': []},
      requiredArgs: const {'id'},
      run: (run) => _screens.open(run.required('id')),
    ),
    operation(
      'back',
      label: 'Show the screen before',
      run: (run) async => _screens.back(),
    ),
    operation(
      'add',
      label: 'Add an empty screen',
      // `id` is wanted, not promised; `name` is its label.
      args: const {'id': [], 'name': []},
      run: (run) =>
          _screens.add(id: run.arg('id'), name: run.arg('name') ?? ''),
    ),
    operation(
      'remove',
      label: 'Remove a screen',
      args: const {'id': []},
      run: (run) => _screens.remove(id: run.arg('id')),
    ),
    operation(
      'rename',
      label: 'Rename a screen',
      args: const {'id': [], 'name': []},
      run: (run) =>
          _screens.rename(id: run.arg('id'), name: run.arg('name') ?? ''),
    ),
    operation(
      'duplicate',
      label: 'Copy a screen',
      args: const {'id': []},
      run: (run) => _screens.duplicate(id: run.arg('id')),
    ),
    operation(
      'startup',
      label: 'Set which screen the launcher opens on',
      // `id` is the screen to start on, empty to keep it; `remember` opens on
      // the screen shown last instead.
      args: const {
        'id': [],
        'remember': ['true', 'false'],
      },
      run: (run) => _screens.startup(
        id: run.arg('id'),
        remember: run.optionalFlag('remember'),
      ),
    ),
  ];
}
