import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/home_button/home_button.dart';
import 'package:openlauncher/features/remote/remote_config_dialog.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) => open(Navigator.of(context));

  static Future<void> open(NavigatorState navigator) =>
      navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  /// Runs automatic setup behind a progress dialog, then reports the result.
  Future<void> _runSetup(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Setting up…'),
          content: Text(
            'If the TV asks whether to allow USB debugging, tick '
            '"Always allow" and choose Allow.',
          ),
        ),
      ),
    );
    SetupResult result;
    try {
      result = await ref.read(launcherPlatformProvider).runAutomaticSetup();
    } on Object catch (error) {
      result = SetupResult(outcome: SetupOutcome.failed, detail: '$error');
    }
    ref.invalidate(homeButtonEnabledProvider);
    ref.invalidate(canManageHomeButtonProvider);
    // Setup also lets the launcher see notifications and what is playing.
    ref.invalidate(notificationAccessProvider);
    ref.invalidate(nowPlayingProvider);
    navigator.pop();
    if (!context.mounted) return;

    final (title, message) = switch (result.outcome) {
      SetupOutcome.done => (
        'All set',
        'The Home button on your remote now opens OpenLauncher.',
      ),
      SetupOutcome.adbUnavailable => (
        'USB debugging is off',
        'OpenLauncher sets itself up through the TV\'s debugging service.\n\n'
            'In TV settings, go to System → About and press OK on the build '
            'number seven times. Then turn on USB debugging in System → '
            'Developer options, and try again.',
      ),
      SetupOutcome.notAuthorised => (
        'The TV did not allow it',
        'Try again, and when the TV asks whether to allow USB debugging, '
            'tick "Always allow" and choose Allow.',
      ),
      SetupOutcome.failed => (
        'Setup did not finish',
        result.detail ?? 'Something went wrong. Try again.',
      ),
    };
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _setHomeButton(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final canManage = await ref.read(canManageHomeButtonProvider.future);
    if (!context.mounted) return;
    if (!canManage) {
      // Turning it on needs setup first; turning it off without setup can
      // only be done in the TV's own settings.
      if (enabled) return _runSetup(context, ref);
      await ref.read(launcherPlatformProvider).openHomeButtonSettings();
      return;
    }
    await ref.read(launcherPlatformProvider).setHomeButtonEnabled(enabled);
    ref.invalidate(homeButtonEnabledProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeEnabled = ref.watch(homeButtonEnabledProvider).value ?? false;
    final canManage = ref.watch(canManageHomeButtonProvider).value ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListTileTheme(
            data: ListTileThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 27),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                SwitchListTile(
                  autofocus: true,
                  secondary: const Icon(Icons.home_outlined),
                  title: const Text('Home button opens OpenLauncher'),
                  subtitle: Text(
                    homeEnabled
                        ? 'On'
                        : canManage
                        ? 'Off'
                        : 'Off. Turning it on runs automatic setup.',
                  ),
                  value: homeEnabled,
                  onChanged: (value) => _setHomeButton(context, ref, value),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_fix_high),
                  title: const Text('Set up automatically'),
                  subtitle: const Text(
                    'Turns on the Home button, notifications, now playing, '
                    'app widgets and force stop, in one step.',
                  ),
                  onTap: () => _runSetup(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Customise from your phone'),
                  subtitle: const Text(
                    'Arrange apps, folders, widgets and sidebars, and '
                    'choose pictures.',
                  ),
                  onTap: () => RemoteConfigDialog.show(context),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('TV settings'),
                  onTap: () => ref
                      .read(launcherPlatformProvider)
                      .openHomeButtonSettings(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
