import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';

/// The layers made while running, and the popup an action fired in.
class LayerOperationsManager implements OperationsManager {
  LayerOperationsManager(this._ref);

  final Ref _ref;

  ScreenLayers get _layers => _ref.read(layersProvider.notifier);

  // `of` is a component id; empty for the one it fired from.
  static const _of = {'of': <String>[]};

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'newLayer',
      label: 'Create a new layer',
      args: const {
        'blur': [],
        'dim': [],
        'modal': ['true', 'false'],
      },
      run: (run) async {
        _layers.create(
          blur: run.number('blur'),
          dim: run.number('dim'),
          modal: run.flag('modal'),
        );
        return null;
      },
    ),
    Operation(
      name: 'toLayer',
      label: 'Move a component to the top layer',
      args: _of,
      run: (run) async {
        if (run.arg('of') ?? run.component case final component?) {
          _layers.moveToTop(component);
        }
        return null;
      },
    ),
    Operation(
      name: 'closeLayer',
      label: "Take a component's layer away",
      args: _of,
      run: (run) async {
        _layers.close(run.arg('of') ?? run.component);
        return null;
      },
    ),
    Operation(
      name: 'closePopup',
      label: 'Close the popup it fired in',
      run: (run) async {
        run.screen?.close();
        return null;
      },
    ),
  ];
}
