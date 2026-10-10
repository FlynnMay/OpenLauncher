import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/selection.dart';

/// Changes the layout through the launcher's own config controller, which
/// shows the change at once and, in the browser, sends it to the TV.
Future<void> changeLayout(
  BuildContext context,
  WidgetRef ref,
  Layout Function(Layout layout) change,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  try {
    await ref.read(configProvider.notifier).setLayout(change(layout));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    // Back to what the TV has.
    ref.invalidate(configProvider);
  }
}

/// Puts what was dragged where it was dropped, or says why it cannot go
/// there. A new folder is given its name first.
Future<void> placeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
  Drop drop,
) async {
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  if (refusal(layout, dragged.item, drop.pane) case final reason?) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    return;
  }
  var panel = dragged.panel;
  if (panel != null) {
    final name = await _askName(context, panel.title);
    if (name == null || !context.mounted) return;
    panel = Panel(id: panel.id, title: name, root: panel.root);
  }
  await changeLayout(
    context,
    ref,
    (layout) => dropItem(layout, dragged.item, drop, panel: panel),
  );
}

/// Takes what was dragged off the TV.
Future<void> removeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
) =>
    changeLayout(context, ref, (layout) => removeItem(layout, dragged.item.id));

/// Takes everything that is picked out off the TV.
Future<void> removeSelected(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(selectionProvider);
  if (ids.isEmpty) return;
  ref.read(selectionProvider.notifier).clear();
  await changeLayout(context, ref, (layout) => ids.fold(layout, removeItem));
}

Future<String?> _askName(BuildContext context, String suggested) {
  final name = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Name of the folder'),
      content: TextField(
        controller: name,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, name.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
