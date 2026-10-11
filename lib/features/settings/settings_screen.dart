import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/remote/remote_config_dialog.dart';

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
    final said = await _do(ref, const Act('setup'));
    navigator.pop();
    if (!context.mounted || said == null) return;
    // Its heading, then the rest.
    final (title, message) = switch (said.indexOf('\n')) {
      -1 => ('Automatic setup', said),
      final at => (said.substring(0, at), said.substring(at + 1)),
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
      await _do(ref, const Act('tvSettings'));
      return;
    }
    await _do(ref, Act('homeButton', {'enabled': enabled}));
  }

  /// Does [act] as anything on the screen would; what it says, or what
  /// went wrong, comes back.
  static Future<String?> _do(WidgetRef ref, Act act) async {
    try {
      return await ref.read(actionRunnerProvider).run(act);
    } on Object catch (error) {
      return 'It could not be done\n$error';
    }
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
                  onTap: () => _do(ref, const Act('tvSettings')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
