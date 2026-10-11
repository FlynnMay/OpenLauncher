import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
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
  var folder = dragged.folder, item = dragged.item;
  if (folder != null) {
    final name = await askName(context, folder.title);
    if (name == null || !context.mounted) return;
    folder = folderPane(layout.paneIdFor(name, 'folder'), title: name);
    // Point the card at the folder's final id.
    item = item.copyWith(
      id: freeId(slugOf(name), {...layout.itemIds, folder.id}),
      vars: {
        ...item.vars,
        Component.sourceVar: Variable(folder.id, type: VarType.entity),
      },
    );
  }
  await changeLayout(
    context,
    ref,
    (layout) => dropItem(layout, item, drop, folder: folder),
  );
}

/// Adds a sidebar on [edge] if missing and selects it, which holds it open.
Future<void> addBar(BuildContext context, WidgetRef ref, String edge) async {
  await changeLayout(context, ref, (layout) => withBar(layout, edge));
  if (!context.mounted) return;
  final layout = ref.read(configProvider).value?.layout;
  final selection = ref.read(selectionProvider.notifier);
  switch (layout == null ? null : barOn(layout, edge)) {
    case final bar?:
      selection.tap(bar.id, adding: false);
    case null:
      selection.clear();
  }
}

/// Adds a sidebar on the first free edge.
Future<void> addBarSomewhere(BuildContext context, WidgetRef ref) async {
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  if (freeEdges(layout).firstOrNull case final edge?) {
    await addBar(context, ref, edge);
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
