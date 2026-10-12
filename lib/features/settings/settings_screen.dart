import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/updates/updates.dart';
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
    final said = await _do(ref, 'setup');
    navigator.pop();
    if (!context.mounted || said == null) return;
    // First line is the heading.
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
      // Enabling needs setup; disabling without it is only possible in TV
      // settings.
      if (enabled) return _runSetup(context, ref);
      await _do(ref, 'tvSettings');
      return;
    }
    await _do(ref, 'homeButton', {'enabled': enabled});
  }

  /// Checks for an update, or offers the one found and installs it.
  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final update = ref.read(updateStateProvider);
    if (update.busy) return;
    if (!update.available) {
      await _do(ref, 'check', const {}, 'updates');
      return;
    }
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('OpenLauncher ${update.latest}'),
        content: SingleChildScrollView(
          child: Text(
            update.notes.isEmpty
                ? 'The launcher restarts when the update is installed.'
                : update.notes,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    // The tile says how it goes, and why if it fails.
    if (install == true) await _do(ref, 'install', const {}, 'updates');
  }

  /// Has [entity] do [action]; returns its message or the error.
  static Future<String?> _do(
    WidgetRef ref,
    String action, [
    Map<String, Object?> args = const {},
    String entity = 'system',
  ]) async {
    try {
      return await ref
          .read(actionRunnerProvider)
          .run(Act(action, {entityArg: entity, ...args}));
    } on Object catch (error) {
      return 'It could not be done\n$error';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeEnabled = ref.watch(homeButtonEnabledProvider).value ?? false;
    final canManage = ref.watch(canManageHomeButtonProvider).value ?? false;
    final update = ref.watch(updateStateProvider);
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
                    'Arrange apps, folders, components and sidebars, and '
                    'choose pictures.',
                  ),
                  onTap: () => RemoteConfigDialog.show(context),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('Updates'),
                  subtitle: Text(
                    update.available && update.status == UpdateStatus.idle
                        ? '${update.summary}. Press to install.'
                        : update.summary,
                  ),
                  onTap: () => _update(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('TV settings'),
                  onTap: () => _do(ref, 'tvSettings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
