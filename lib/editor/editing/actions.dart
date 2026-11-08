import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_registry.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/dragging.dart';
import 'package:openlauncher/editor/editing/history.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';
import 'package:openlauncher/editor/editing/selection.dart';
import 'package:openlauncher/editor/tv/tv_api.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/editing/docked_prefabs.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/editing/prefab_edit.dart';
import 'package:openlauncher_domain/slice/slice.dart';

/// Where node [id] is in what is being edited: on the screens, or in the open
/// prefab as the shown variant has it.
Address addressOf(WidgetRef ref, String id) {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null) return LayoutAddress(id);
  final shown = ref.read(prefabModeProvider)?.variant;
  return PrefabAddress(
    prefab.id,
    variant: prefab.isBase(shown) ? null : prefab.variantNamed(shown),
    child: id == prefab.root.id ? null : id,
  );
}

/// Does [command] on the config. The TV does it, so its rules hold and its
/// other editors are not overwritten; undo is the TV's, and the editor keeps
/// what was selected and open. A refusal is shown, not thrown.
Future<void> runCommand(
  BuildContext context,
  WidgetRef ref,
  Command command,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(commandsProvider).run(command);
  } on CommandRefused catch (refused) {
    messenger.showSnackBar(SnackBar(content: Text(refused.message)));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    ref.invalidate(configProvider);
  }
}

/// Does [edits] as one step, the first done first.
Future<void> runEdits(
  BuildContext context,
  WidgetRef ref,
  List<SliceEdit> edits,
) =>
    edits.isEmpty ? Future.value() : runCommand(context, ref, EditSlice(edits));

/// Does [opsByNode] to the nodes, by id, as one step; the TV applies them.
Future<void> editNodes(
  BuildContext context,
  WidgetRef ref,
  Map<String, List<SliceOp>> opsByNode,
) {
  final edits = [
    for (final MapEntry(:key, :value) in opsByNode.entries)
      if (value.isNotEmpty) SliceEdit(addressOf(ref, key), value),
  ];
  return runEdits(context, ref, edits);
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

/// Sets settings to whole new values, as the editor holds them: a picture
/// by its address on the TV is sent as the id of its file.
Future<void> setSettings(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> values,
) => runEdits(context, ref, [
  SliceEdit(const ConfigAddress(), [
    for (final MapEntry(:key, :value) in TvApi.withMediaIds(values).entries)
      SetSetting(key, value),
  ]),
]);

/// Changes the config by [how], and sets the settings that came out
/// different, each to its whole new value.
Future<void> changeSettings(
  BuildContext context,
  WidgetRef ref,
  LauncherConfig Function(LauncherConfig config) how,
) {
  final config = ref.read(configProvider).value;
  if (config == null) return Future.value();
  final was = config.open, now = how(config).open;
  return setSettings(context, ref, {
    for (final key in LauncherConfig.openKeys)
      if (jsonEncode(now[key]) != jsonEncode(was[key])) key: now[key],
  });
}

/// Sets entries of the settings that are maps, each as `(setting, entry,
/// value)`; a null value takes the entry away.
Future<void> setEntries(
  BuildContext context,
  WidgetRef ref,
  List<(String, String, String?)> entries,
) => runEdits(context, ref, [
  SliceEdit(const ConfigAddress(), [
    for (final (setting, entry, value) in entries)
      SetEntry(
        setting,
        entry,
        setting == 'iconOverrides' && value != null
            ? TvApi.mediaIdOf(value)
            : value,
      ),
  ]),
]);

/// Calls app or node [id] [name]; none, or empty, restores its own name.
Future<void> setName(
  BuildContext context,
  WidgetRef ref,
  String id,
  String? name,
) {
  final trimmed = name?.trim() ?? '';
  return setEntries(context, ref, [
    ('names', id, trimmed.isEmpty ? null : trimmed),
  ]);
}

/// Gives [id] the picture at [path]; none takes its own away. It stops
/// borrowing another's.
Future<void> setIconOverride(
  BuildContext context,
  WidgetRef ref,
  String id,
  String? path,
) => setEntries(context, ref, [
  ('iconOverrides', id, path),
  ('iconSources', id, null),
]);

/// Makes [id] use the picture of [from]; none stops it.
Future<void> setIconSource(
  BuildContext context,
  WidgetRef ref,
  String id,
  String? from,
) => setEntries(context, ref, [
  ('iconSources', id, from),
  if (from != null) ('iconOverrides', id, null),
]);

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
  final exists = findItems(layout, {item.id}).isNotEmpty;
  await runEdits(context, ref, [
    // A node already there is moved: cut, then put.
    if (exists) SliceEdit(addressOf(ref, item.id), const [RemoveNode()]),
    SliceEdit(addressOf(ref, drop.before ?? drop.container), [
      Insert(
        drop.before == null ? Where.into : Where.before,
        NodeClip(item, cut: exists),
        x: drop.x,
        y: drop.y,
        rect: drop.rect,
        size: drop.size,
      ),
    ]),
    // The container a new card opens is docked on the startup screen.
    if (opens != null)
      SliceEdit(addressOf(ref, layout.start.root.id), [
        Insert(Where.into, NodeClip(opens)),
      ]),
  ]);
}

/// Docks a container made from [template] to [edge] if none is, and selects it,
/// which holds it open.
Future<void> dockPrefab(
  BuildContext context,
  WidgetRef ref,
  String edge,
  Prefab template,
) async {
  final before = ref.read(editedLayoutProvider);
  if (before == null) return;
  final existing = dockedOn(before, edge);
  final id = existing?.id ?? before.containerIdFor(edge);
  if (existing == null) {
    await runEdits(context, ref, [
      SliceEdit(addressOf(ref, before.start.root.id), [
        Insert(Where.into, NodeClip(dockedInstance(template, id, dock: edge))),
      ]),
    ]);
  }
  if (!context.mounted) return;
  ref.read(selectionProvider.notifier).tap(id, adding: false);
}

/// Docks a container made from [template] to the first free edge.
Future<void> dockPrefabSomewhere(
  BuildContext context,
  WidgetRef ref,
  Prefab template,
) async {
  final layout = ref.read(configProvider).value?.layout;
  if (layout == null) return;
  if (freeEdges(layout).firstOrNull case final edge?) {
    await dockPrefab(context, ref, edge, template);
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
) => runEdits(context, ref, [
  SliceEdit(addressOf(ref, dragged.item.id), const [RemoveNode()]),
]);

Future<void> removeSelected(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(selectionProvider);
  if (ids.isEmpty) return;
  // Still selected when the change is recorded, so undo selects them again.
  await runEdits(context, ref, [
    for (final id in ids) SliceEdit(addressOf(ref, id), const [RemoveNode()]),
  ]);
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
  } on CommandRefused catch (refused) {
    messenger.showSnackBar(SnackBar(content: Text(refused.message)));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
  }
}
