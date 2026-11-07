import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';

/// The launcher's own settings.
class SettingsOperationsManager extends OperationsManager {
  @override
  String get area => 'launcher://settings';

  @override
  late final List<Operation> operations = [
    operation(
      'open',
      label: "Open the launcher's settings",
      run: (run) async {
        await run.screen?.openSettings();
        return null;
      },
    ),
  ];
}
