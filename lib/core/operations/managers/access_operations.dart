import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What the TV allows the launcher.
class AccessOperationsManager extends OperationsManager {
  AccessOperationsManager(this._ref);

  final Ref _ref;

  LauncherPlatform get _platform => _ref.read(launcherPlatformProvider);

  @override
  String get area => 'os://access';

  @override
  late final List<Operation> operations = [
    // The message's first line is its heading.
    operation(
      'change',
      label: "Allow or withdraw a permission in the TV's settings",
      args: {
        'access': [for (final access in Access.values) access.name],
      },
      requiredArgs: const {'access'},
      run: (run) async {
        final access = Access.values.byName(run.required('access'));
        try {
          await _platform.changeAccess(access);
        } on PlatformException {
          return 'This TV has no screen for it\n'
              'It can be allowed from a computer instead. The OpenLauncher '
              'README says how.';
        }
        _ref.invalidate(accessProvider(access));
        return null;
      },
    ),
  ];
}
