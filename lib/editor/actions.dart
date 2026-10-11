import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/dragging.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/selection.dart';

/// Changes the layout through the config controller, which updates the screen
/// and sends it to the TV.
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
    // Reload from the TV.
    ref.invalidate(configProvider);
  }
}

/// Places what was dragged, or reports why it cannot go there. A new folder
/// is named first.
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
  var panel = dragged.panel, item = dragged.item;
  if (panel != null) {
    final name = await askName(context, panel.title);
    if (name == null || !context.mounted) return;
    panel = Panel.empty(layout.panelIdFor(name), title: name);
    // Point the card at the folder's final id.
    item = item.copyWith(
      id: layout.itemIdFor(name),
      vars: {
        ...item.vars,
        Component.sourceVar: Variable(panel.id, type: VarType.entity),
      },
    );
  }
  await changeLayout(
    context,
    ref,
    (layout) => dropItem(layout, item, drop, panel: panel),
  );
}

/// Adds a sidebar on edge [id] if missing and opens it for editing.
Future<void> addBar(BuildContext context, WidgetRef ref, String id) async {
  await changeLayout(context, ref, (layout) => withBar(layout, id));
  if (!context.mounted) return;
  ref.read(selectionProvider.notifier).clear();
  ref.read(barProvider.notifier).set(id);
}

/// Adds a sidebar on the first free edge.
Future<void> addBarSomewhere(BuildContext context, WidgetRef ref) async {
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  if (freeEdges(layout).firstOrNull case final id?) {
    await addBar(context, ref, id);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Every edge has a sidebar already.')),
    );
  }
}

Future<void> removeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
) =>
    changeLayout(context, ref, (layout) => removeItem(layout, dragged.item.id));

Future<void> removeSelected(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(selectionProvider);
  if (ids.isEmpty) return;
  ref.read(selectionProvider.notifier).clear();
  await changeLayout(context, ref, (layout) => ids.fold(layout, removeItem));
}

/// Asks for a name; null if cancelled.
Future<String?> askName(
  BuildContext context,
  String suggested, {
  String title = 'Name of the folder',
}) {
  final name = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
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
