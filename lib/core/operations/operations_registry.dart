import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/operations/managers/access_operations.dart';
import 'package:openlauncher/core/operations/managers/app_operations.dart';
import 'package:openlauncher/core/operations/managers/input_operations.dart';
import 'package:openlauncher/core/operations/managers/layout_operations.dart';
import 'package:openlauncher/core/operations/managers/media_operations.dart';
import 'package:openlauncher/core/operations/managers/overlay_operations.dart';
import 'package:openlauncher/core/operations/managers/screen_operations.dart';
import 'package:openlauncher/core/operations/managers/settings_operations.dart';
import 'package:openlauncher/core/operations/managers/tv_settings_operations.dart';
import 'package:openlauncher/core/operations/managers/update_operations.dart';
import 'package:openlauncher/core/operations/managers/variable_operations.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/operations/web_operation.dart';
import 'package:openlauncher/core/services/services.dart';

/// Every operation of every manager, by name.
class OperationsRegistry {
  /// Throws [StateError] if two operations share an address, or one is not
  /// in its manager's area.
  OperationsRegistry(Iterable<OperationsManager> managers, {this.web}) {
    for (final manager in managers) {
      for (final operation in manager.operations) {
        if (!operation.address.startsWith('${manager.area}/')) {
          throw StateError('"${operation.address}" is not in ${manager.area}');
        }
        if (_byName.containsKey(operation.address)) {
          throw StateError('Two operations are named "${operation.address}"');
        }
        _byName[operation.address] = operation;
      }
    }
  }

  final _byName = <String, Operation>{};

  /// What any `http(s)://` address runs.
  final Operation? web;

  Operation? operator [](String name) =>
      isWebAddress(name) ? web : _byName[name];

  Iterable<Operation> get all => _byName.values;

  /// The areas there are, in the order their operations were added.
  Iterable<String> get areas => {for (final operation in all) operation.area};

  /// What is at [area], e.g. `launcher://overlay`.
  List<Operation> inArea(String area) => [
    for (final operation in all)
      if (operation.area == area) operation,
  ];
}

/// The managers the registry is built from. A new group of operations is one
/// manager added here.
final operationsManagersProvider = Provider<List<OperationsManager>>((ref) {
  return [
    AppOperationsManager(ref.watch(appServiceProvider)),
    InputOperationsManager(ref.watch(inputServiceProvider)),
    MediaOperationsManager(ref.watch(mediaServiceProvider)),
    AccessOperationsManager(ref.watch(accessServiceProvider)),
    SettingsOperationsManager(),
    TvSettingsOperationsManager(ref.watch(tvSettingsServiceProvider)),
    UpdateOperationsManager(ref),
    OverlayOperationsManager(ref.watch(overlayServiceProvider)),
    ScreenOperationsManager(ref.watch(screenServiceProvider)),
    VariableOperationsManager(ref.watch(variableServiceProvider)),
    LayoutOperationsManager(ref.watch(layoutServiceProvider)),
  ];
});

final operationsRegistryProvider = Provider<OperationsRegistry>(
  (ref) => OperationsRegistry(
    ref.watch(operationsManagersProvider),
    web: webOperation(ref.watch(httpServiceProvider)),
  ),
);
