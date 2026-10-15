import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/features/remote/remote_config_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) => open(Navigator.of(context));

  static Future<void> open(NavigatorState navigator) =>
      navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  /// Has the TV show where [access] is changed; says so if it has nowhere.
  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    Access access,
  ) async {
    final said = await _do(ref, 'os://access/change', {'access': access.name});
    if (!context.mounted || said == null) return;
    // First line is the heading.
    final (title, message) = switch (said.indexOf('\n')) {
      -1 => (access.label, said),
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

  /// Checks for an update, or offers the one found and installs it.
  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final update = ref.read(updateStateProvider);
    if (update.busy) return;
    if (!update.available) {
      await _do(ref, 'launcher://updates/check');
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
    if (install == true) await _do(ref, 'launcher://updates/install');
  }

  /// Calls [address]; returns its message or the error.
  static Future<String?> _do(
    WidgetRef ref,
    String address, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await ref.read(actionRunnerProvider).run(Act(address, args));
    } on Object catch (error) {
      return 'It could not be done\n$error';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const _Heading('Permissions'),
                for (final access in Access.values)
                  ListTile(
                    autofocus: access == Access.values.first,
                    leading: Icon(switch (access) {
                      Access.homeButton => Icons.home_outlined,
                      Access.notifications => Icons.notifications_outlined,
                    }),
                    title: Text(access.label),
                    subtitle: Text(access.use),
                    trailing: Text(switch (ref
                        .watch(accessProvider(access))
                        .value) {
                      true => 'Allowed',
                      false => 'Not allowed',
                      null => '',
                    }),
                    onTap: () => _change(context, ref, access),
                  ),
                const _Heading('Launcher'),
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
                  onTap: () => _do(ref, 'os://settings/open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
