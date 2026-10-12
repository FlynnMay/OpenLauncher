import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/dragging.dart';
import 'package:openlauncher/editor/editing/history.dart';
import 'package:openlauncher/editor/editing/layout_edit.dart';
import 'package:openlauncher/editor/editing/prefab_actions.dart';
import 'package:openlauncher/editor/editing/prefab_edit.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';
import 'package:openlauncher/editor/editing/selection.dart';

/// Changes what is being edited, the layout or the open prefab, through the
/// config controller, which updates the screen and sends it to the TV.
Future<void> changeLayout(
  BuildContext context,
  WidgetRef ref,
  Layout Function(Layout layout) change,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final layout = ref.read(editedLayoutProvider);
  if (layout == null) return;
  final prefab = ref.read(editedPrefabProvider);
  try {
    if (prefab == null) {
      await ref.read(configProvider.notifier).setLayout(change(layout));
    } else if (await saveEdited(ref, prefab, change(layout))
        case final reason?) {
      messenger.showSnackBar(SnackBar(content: Text(reason)));
    }
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    // Reload from the TV.
    ref.invalidate(configProvider);
  }
}

/// Changes the config through its controller; a change the TV refuses is
/// reported and the TV's config read again.
Future<void> changeConfig(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(ConfigController controller) change,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await change(ref.read(configProvider.notifier));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    ref.invalidate(configProvider);
  }
}

/// Why [dragged] cannot go into pane [paneId] of what is being edited, or
/// null.
String? whyNot(WidgetRef ref, Dragged dragged, String paneId) {
  final layout = ref.read(editedLayoutProvider);
  if (layout == null) return 'Nothing to add it to.';
  final prefab = ref.read(editedPrefabProvider);
  if (prefab != null) {
    if (dragged.sidebar || dragged.folder != null) {
      return 'A prefab cannot hold a sidebar or a new folder.';
    }
    if (paneId == prefabStageId && dragged.item.id != prefab.root.id) {
      return 'Drop it inside the prefab.';
    }
    final prefabs = ref.read(prefabsProvider);
    if (dragged.item.all.any(
      (part) =>
          part.isInstance && holdsPrefab(part.prefab!, prefab.id, prefabs),
    )) {
      return 'A prefab cannot contain itself.';
    }
  }
  return refusal(layout, dragged.item, paneId);
}

/// Places what was dragged, or reports why it cannot go there. A new folder
/// is named first.
Future<void> placeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
  Drop drop,
) async {
  final layout = ref.read(editedLayoutProvider);
  if (layout == null) return;
  if (whyNot(ref, dragged, drop.pane) case final reason?) {
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
  // Still selected when the change is recorded, so undo selects them again.
  await changeLayout(context, ref, (layout) => ids.fold(layout, removeItem));
  ref.read(selectionProvider.notifier).clear();
}

/// Undoes the last change, or redoes the last one undone.
Future<void> stepHistory(
  BuildContext context,
  WidgetRef ref, {
  required bool back,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final history = ref.read(historyProvider.notifier);
  try {
    await (back ? history.undo() : history.redo());
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
  }
}
