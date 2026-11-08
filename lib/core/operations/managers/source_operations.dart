import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// Sources of packs: where their values come from.
class SourceOperationsManager extends OperationsManager {
  SourceOperationsManager(this._sources);

  final SourceService _sources;

  @override
  String get area => 'launcher://sources';

  @override
  late final List<Operation> operations = [
    operation(
      'fetch',
      label: 'Fetch a source again',
      args: {'source': const []},
      requiredArgs: const {'source'},
      run: (run) => _sources.fetchAgain(run.entityId, run.required('source')),
    ),
  ];
}
