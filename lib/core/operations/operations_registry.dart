import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/operations/managers/app_operations.dart';
import 'package:openlauncher/core/operations/managers/input_operations.dart';
import 'package:openlauncher/core/operations/managers/layer_operations.dart';
import 'package:openlauncher/core/operations/managers/layout_operations.dart';
import 'package:openlauncher/core/operations/managers/media_operations.dart';
import 'package:openlauncher/core/operations/managers/system_operations.dart';
import 'package:openlauncher/core/operations/managers/update_operations.dart';
import 'package:openlauncher/core/operations/managers/variable_operations.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Every operation of every manager, by name.
class OperationsRegistry {
  /// Throws [StateError] if two operations share a name.
  OperationsRegistry(Iterable<OperationsManager> managers) {
    for (final manager in managers) {
      for (final operation in manager.operations) {
        if (_byName.containsKey(operation.name)) {
          throw StateError('Two operations are named "${operation.name}"');
        }
        _byName[operation.name] = operation;
      }
    }
  }

  final _byName = <String, Operation>{};

  Operation? operator [](String name) => _byName[name];

  Iterable<Operation> get all => _byName.values;
}

/// The managers the registry is built from. A new group of operations is one
/// manager added here.
final operationsManagersProvider = Provider<List<OperationsManager>>((ref) {
  final platform = ref.watch(launcherPlatformProvider);
  return [
    AppOperationsManager(platform),
    InputOperationsManager(platform),
    MediaOperationsManager(platform),
    SystemOperationsManager(ref),
    UpdateOperationsManager(ref),
    LayerOperationsManager(ref),
    VariableOperationsManager(ref),
    LayoutOperationsManager(ref),
  ];
});

final operationsRegistryProvider = Provider<OperationsRegistry>(
  (ref) => OperationsRegistry(ref.watch(operationsManagersProvider)),
);
