import 'package:openlauncher/core/operations/operation.dart';

/// Owns a related group of operations, e.g. everything done to an app.
abstract interface class OperationsManager {
  List<Operation> get operations;
}
