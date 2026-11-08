import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/config_commands.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/commands/node_commands.dart';
import 'package:openlauncher_domain/commands/prefab_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/editing/prefab_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/layout_repair.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/validation/validation.dart';

/// What an edit of the prefab library leaves: the layout and the user's own
/// prefabs.
typedef LibraryState = ({Layout layout, List<Prefab> prefabs});

/// An edit that changes the layout and the user's prefabs together. It is held
/// to the rules of a layout for the faults it adds, and its undo is the patch
/// and the prefab changes that put both back.
abstract class PrefabLibraryEdit extends Command {
  const PrefabLibraryEdit();

  /// The layout and the user's prefabs [own] once this is done, given every
  /// prefab in use.
  LibraryState change(
    Layout layout,
    List<Prefab> own,
    Map<String, Prefab> inUse,
  );

  @override
  Document edit(Document document) {
    final done = change(
      document.layout,
      Prefab.listFromJson(document.settings[ChangePrefabs.settingName]),
      document.prefabs,
    );
    final added = const LayoutValidator().problemsAdded(
      before: document.layout,
      after: done.layout,
    );
    if (added.isNotEmpty) throw CommandRefused(added.first.message);
    return document.copyWith(
      layout: done.layout,
      settings: {
        ...document.settings,
        ChangePrefabs.settingName: [
          for (final prefab in done.prefabs) prefab.toJson(),
        ],
      },
    );
  }

  @override
  Command undoing(Document before) {
    final after = edit(before);
    return Batch([
      PatchLayout.turning(after.layout, before.layout),
      ChangePrefabs.turning(
        after.settings[ChangePrefabs.settingName]! as List<Object?>,
        before.settings[ChangePrefabs.settingName] as List<Object?>? ??
            const [],
      ),
    ]);
  }
}

/// Makes a prefab of a node, which an instance replaces. [size] is what a
/// node placed by its transform is drawn at.
class MakePrefab extends PrefabLibraryEdit {
  const MakePrefab(this.nodeId, this.prefabId, this.name, {this.size});

  factory MakePrefab.fromJson(Json json) => MakePrefab(
    jsonRequired<String>(json, 'node'),
    jsonRequired<String>(json, 'prefab'),
    jsonRequired<String>(json, 'name'),
    size: Extent.fromJson(json['size']),
  );

  static const typeName = 'prefab.make';

  final String nodeId, prefabId, name;
  final Extent? size;

  @override
  String get type => typeName;

  @override
  LibraryState change(
    Layout layout,
    List<Prefab> own,
    Map<String, Prefab> inUse,
  ) {
    final found = findItems(layout, {nodeId});
    if (found.isEmpty) throw const CommandRefused('There is nothing there.');
    if (inUse.containsKey(prefabId)) {
      throw const CommandRefused('A prefab has that id already.');
    }
    final item = found.single.item;
    final made = asPrefab(item, prefabId, name, size: size);
    final replaced = changeItems(layout, {nodeId}, (_, _) => made.instance);
    return (
      // What it holds is no longer on the screen in its own right, and is not
      // put back.
      layout: replaced
          .copyWith(
            removed: {
              ...replaced.removed,
              for (final part in item.all)
                if (part.isInstance)
                  for (final id in part.handed)
                    if (replaced.container(id) == null) id,
            },
          )
          .normalised(),
      prefabs: [...own, made.prefab],
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'node': nodeId,
    'prefab': prefabId,
    'name': name,
    if (size != null) 'size': size!.toJson(),
  };
}

/// Deletes a prefab of the user's, unpacking its instances where they stand.
class DeletePrefab extends PrefabLibraryEdit {
  const DeletePrefab(this.prefabId);

  factory DeletePrefab.fromJson(Json json) =>
      DeletePrefab(jsonRequired<String>(json, 'prefab'));

  static const typeName = 'prefab.delete';

  final String prefabId;

  @override
  String get type => typeName;

  @override
  LibraryState change(
    Layout layout,
    List<Prefab> own,
    Map<String, Prefab> inUse,
  ) {
    if (!inUse.containsKey(prefabId)) {
      throw const CommandRefused('That prefab is gone.');
    }
    final done = withoutPrefab(layout, own, inUse, prefabId);
    return (layout: done.layout.normalised(), prefabs: done.prefabs);
  }

  @override
  Map<String, Object?> toJson() => {'type': type, 'prefab': prefabId};
}

/// Renames part [from] of a prefab to [to], and everything that names it.
class RenamePart extends PrefabLibraryEdit {
  const RenamePart(this.prefabId, this.from, this.to);

  factory RenamePart.fromJson(Json json) => RenamePart(
    jsonRequired<String>(json, 'prefab'),
    jsonRequired<String>(json, 'from'),
    jsonRequired<String>(json, 'to'),
  );

  static const typeName = 'prefab.renamePart';

  final String prefabId, from, to;

  @override
  String get type => typeName;

  @override
  LibraryState change(
    Layout layout,
    List<Prefab> own,
    Map<String, Prefab> inUse,
  ) {
    final prefab =
        inUse[prefabId] ?? (throw const CommandRefused('That prefab is gone.'));
    if (!prefab.root.all.any((part) => part.id == from)) {
      throw const CommandRefused('That part is gone.');
    }
    if (prefab.root.all.any((part) => part.id == to)) {
      throw CommandRefused('Another part of the prefab is called "$to".');
    }
    return withPartRenamed(layout, withPrefab(own, prefab), prefab, from, to);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'prefab': prefabId,
    'from': from,
    'to': to,
  };
}

/// The commands on the library of prefabs, by the name they go by in JSON.
final Map<String, CommandReader> prefabLibraryCommandReaders = {
  MakePrefab.typeName: MakePrefab.fromJson,
  DeletePrefab.typeName: DeletePrefab.fromJson,
  RenamePart.typeName: RenamePart.fromJson,
};
