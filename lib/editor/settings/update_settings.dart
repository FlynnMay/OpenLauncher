import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';

/// Updates of the launcher itself: what is done about them, where the TV
/// stands, and the two things to do. The TV does both.
class UpdateSettings extends ConsumerStatefulWidget {
  const UpdateSettings({super.key});

  @override
  ConsumerState<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends ConsumerState<UpdateSettings> with Busy {
  /// Calls `launcher://updates/<verb>` and shows what it says.
  Future<void> _do(String verb) => whileBusy(() async {
    final messenger = ScaffoldMessenger.of(context);
    final said = await ref
        .read(actionRunnerProvider)
        .run(Act('${Operation.launcher}updates/$verb'));
    if (said == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(said.replaceAll('\n', ': '))),
    );
  });

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();
    final update = ref.watch(updateStateProvider);
    final working = busy || update.busy;
    return Section('Updates', open: false, [
      ...optionFields(
        options: UpdateOptions.options,
        values: config.updates.toJson(),
        onChanged: (updates) => changeConfig(
          context,
          ref,
          (controller) => controller.patch({'updates': updates}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(update.summary),
      ),
      if (update.status == UpdateStatus.downloading)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(value: update.progress),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: working ? null : () => _do('check'),
            child: const Text('Check for updates'),
          ),
          if (update.available)
            FilledButton(
              onPressed: working ? null : () => _do('install'),
              child: const Text('Install'),
            ),
        ],
      ),
    ]);
  }
}
