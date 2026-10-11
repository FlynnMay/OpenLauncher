import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/device_sources.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// The launcher's own settings and its hold on the TV.
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
      name: 'runSetup',
      label: 'Set the launcher up automatically',
      onDevice: true,
      run: (run) async {
        SetupResult result;
        try {
          result = await _platform.runAutomaticSetup();
        } on Object catch (error) {
          result = SetupResult(outcome: SetupOutcome.failed, detail: '$error');
        }
        // Setup changes what the launcher can see.
        _ref
          ..invalidate(homeButtonEnabledProvider)
          ..invalidate(canManageHomeButtonProvider)
          ..invalidate(notificationAccessProvider)
          ..invalidate(nowPlayingProvider);
        return switch (result.outcome) {
          SetupOutcome.done =>
            'All set\n'
                'The Home button on your remote now opens OpenLauncher.',
          SetupOutcome.adbUnavailable =>
            'USB debugging is off\n'
                'OpenLauncher sets itself up through the TV\'s debugging '
                'service.\n\n'
                'In TV settings, go to System → About and press OK on the '
                'build number seven times. Then turn on USB debugging in '
                'System → Developer options, and try again.',
          SetupOutcome.notAuthorised =>
            'The TV did not allow it\n'
                'Try again, and when the TV asks whether to allow USB '
                'debugging, tick "Always allow" and choose Allow.',
          SetupOutcome.failed =>
            'Setup did not finish\n'
                '${result.detail ?? 'Something went wrong. Try again.'}',
        };
      },
    ),
    Operation(
      name: 'setHomeButton',
      label: 'Switch the Home button',
      args: const {
        'enabled': ['true', 'false'],
      },
      onDevice: true,
      run: (run) async {
        await _platform.setHomeButtonEnabled(
          run.flag('enabled', otherwise: true),
        );
        _ref.invalidate(homeButtonEnabledProvider);
        return null;
      },
    ),
    Operation(
      name: 'openTvSettings',
      label: "Open the TV's Home button settings",
      onDevice: true,
      run: (run) async {
        await _platform.openHomeButtonSettings();
        return null;
      },
    ),
  ];
}
