import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_registry.dart';
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
      final startup = ref.read(configProvider).value?.layout.startup;
      final changed = change(layout);
      await ref
          .read(configProvider.notifier)
          .setLayout(
            startup == null ? changed : changed.copyWith(startup: startup),
          );
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

/// Runs the launcher operation [name] and shows what it answers.
Future<void> runLauncher(
  BuildContext context,
  WidgetRef ref,
  String name, [
  Map<String, Object?> args = const {},
]) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(operationsRegistryProvider)[name]
      ?.run(OperationRun(args));
  if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
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

/// Why [dragged] cannot go into container [containerId] of what is being
/// edited, or null.
String? whyNot(WidgetRef ref, Dragged dragged, String containerId) {
  final layout = ref.read(editedLayoutProvider);
  if (layout == null) return 'Nothing to add it to.';
  final prefab = ref.read(editedPrefabProvider);
  if (prefab != null) {
    if (dragged.docking || dragged.opens != null) {
      return 'A prefab cannot hold something new that docks.';
    }
    if (containerId == prefabStageId && dragged.item.id != prefab.root.id) {
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
  return refusal(layout, dragged.item, containerId);
}

/// Places what was dragged, or reports why it cannot go there. A new
/// instance its card opens is named first.
Future<void> placeDragged(
  BuildContext context,
  WidgetRef ref,
  Dragged dragged,
  Drop drop,
) async {
  final layout = ref.read(editedLayoutProvider);
  if (layout == null) return;
  if (whyNot(ref, dragged, drop.container) case final reason?) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    return;
  }
  var opens = dragged.opens, item = dragged.item;
  if (opens != null) {
    final name = await askName(context, opens.name);
    if (name == null || !context.mounted) return;
    opens = opens
        .withId(layout.containerIdFor(name, 'layout'))
        .copyWith(name: name);
    // Point the card at its final id.
    item = item
        .copyWith(id: freeId(slugOf(name), {...layout.itemIds, opens.id}))
        .withVars({
          for (final MapEntry(key: name, value: variable) in item.vars.entries)
            name: variable.type == VarType.entity
                ? Variable(opens.id, type: VarType.entity)
                : variable,
        });
  }
  await changeLayout(
    context,
    ref,
    (layout) => dropItem(layout, item, drop, opens: opens),
  );
}

/// Docks a container made from [template] to [edge] if none is, and selects it,
/// which holds it open.
Future<void> addBar(
  BuildContext context,
  WidgetRef ref,
  String edge,
  Prefab template,
) async {
  await changeLayout(context, ref, (layout) => withBar(layout, edge, template));
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

/// Docks a container made from [template] to the first free edge.
Future<void> addBarSomewhere(
  BuildContext context,
  WidgetRef ref,
  Prefab template,
) async {
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  if (freeEdges(layout).firstOrNull case final edge?) {
    await addBar(context, ref, edge, template);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Every edge has something docked already.')),
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
