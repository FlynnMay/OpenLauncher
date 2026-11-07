import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';

/// The TV's own settings.
class TvSettingsOperationsManager extends OperationsManager {
  TvSettingsOperationsManager(this._tvSettings);

  final TvSettingsService _tvSettings;

  @override
  String get area => 'os://settings';

  @override
  late final List<Operation> operations = [
    operation(
      'open',
      label: "Open the TV's settings",
      run: (run) => _tvSettings.open(),
    ),
  ];
}
