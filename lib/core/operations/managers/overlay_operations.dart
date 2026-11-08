import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// Nodes drawn over the screen.
class OverlayOperationsManager extends OperationsManager {
  OverlayOperationsManager(this._overlays);

  final OverlayService _overlays;

  @override
  String get area => 'launcher://overlay';

  @override
  late final List<Operation> operations = [
    operation(
      'open',
      label: 'Open a node over the screen',
      // `of` is a node id, empty for the one it fired from; `dim` a
      // percentage. Unset, they are the node's Overlay's.
      args: const {
        'of': [],
        'dim': [],
        'blur': [],
        'modal': ['true', 'false'],
      },
      run: (run) => _overlays.open(
        id: run.arg('of') ?? run.component,
        dim: run.optionalNumber('dim'),
        blur: run.optionalNumber('blur'),
        modal: run.optionalFlag('modal'),
      ),
    ),
    operation(
      'close',
      label: 'Close a node over the screen',
      // `of` is a node id; empty, the overlay it fired in, else the top one.
      args: const {'of': []},
      run: (run) =>
          _overlays.close(id: run.arg('of'), component: run.component),
    ),
  ];
}
