import 'package:openlauncher/core/operations/operation.dart';

/// Owns the operations of one area, e.g. everything done to an app. An
/// operation says only its verb; the area gives the rest of its address.
abstract class OperationsManager {
  /// Where its operations are, e.g. `os://apps`.
  String get area;

  List<Operation> get operations;

  /// The operation at `<area>/<verb>`.
  Operation operation(
    String verb, {
    required String label,
    required Future<String?> Function(OperationRun run) run,
    Map<String, List<String>> args = const {},
    Set<String> requiredArgs = const {},
  }) => Operation(
    address: '$area/$verb',
    label: label,
    run: run,
    args: args,
    requiredArgs: requiredArgs,
  );
}
