import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// The launcher's own settings and what the TV allows it.
class SystemOperationsManager implements OperationsManager {
  SystemOperationsManager(this._ref);

  final Ref _ref;

  LauncherPlatform get _platform => _ref.read(launcherPlatformProvider);

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'openSettings',
      label: "Open the launcher's settings",
      run: (run) async {
        await run.screen?.openSettings();
        return null;
      },
    ),
    // The message's first line is its heading.
    Operation(
      name: 'changeAccess',
      label: "Allow or withdraw a permission in the TV's settings",
      args: {
        'access': [for (final access in Access.values) access.name],
      },
      onDevice: true,
      run: (run) async {
        final access = Access.values.asNameMap()[run.arg('access')];
        if (access == null) {
          throw const FormatException('No permission was given');
        }
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
    Operation(
      name: 'openTvSettings',
      label: "Open the TV's settings",
      onDevice: true,
      run: (run) async {
        await _platform.openTvSettings();
        return null;
      },
    ),
  ];
}
