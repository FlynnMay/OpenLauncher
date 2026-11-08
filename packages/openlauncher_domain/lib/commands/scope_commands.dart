import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/commands/prefab_commands.dart';
import 'package:openlauncher_domain/editing/prefab_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

const variantsShareStructure =
    'Variants share the prefab\'s structure, variables and actions. Switch '
    'to the default variant to change them.';

/// Does [command] to one prefab instead of the layout: the command sees the
/// prefab, as [variant] shows it, as a layout of its own, and only that
/// prefab is saved from what it did. What names the prefab's parts elsewhere
/// follows the parts that went.
class InPrefab extends Command {
  const InPrefab(this.prefabId, this.variant, this.command);

  factory InPrefab.fromJson(Json json, CommandReader read) => InPrefab(
    jsonRequired<String>(json, 'prefab'),
    jsonOptional<String>(json, 'variant'),
    read(jsonObject(json['command'])),
  );

  static const typeName = 'scope.prefab';

  final String prefabId;
  final String? variant;
  final Command command;

  @override
  String get type => typeName;

  Prefab _prefabIn(Document document) =>
      document.prefabs[prefabId] ??
      (throw const CommandRefused('That prefab is gone.'));

  Document _scoped(Document document) {
    final prefab = _prefabIn(document);
    return Document(
      layout: prefabAsLayout(prefab, variant),
      settings: document.settings,
      prefabs: document.prefabs,
    );
  }

  @override
  Document edit(Document document) {
    final prefab = _prefabIn(document);
    final scoped = _scoped(document);
    final edited = command.edit(scoped);
    final root =
        prefabRootIn(edited.layout, prefab.root.id) ??
        (throw const CommandRefused('A prefab keeps its root.'));
    final next =
        withEdited(prefab, variant, root) ??
        (throw const CommandRefused(variantsShareStructure));
    final own = withPrefab(
      Prefab.listFromJson(edited.settings[ChangePrefabs.settingName]),
      next,
    );
    final left = {for (final part in next.root.all) part.id};
    final gone = {
      for (final part in prefab.root.all)
        if (!left.contains(part.id)) part.id: null,
    };
    final fixed = gone.isEmpty
        ? (layout: document.layout, prefabs: own)
        : withPartIds(document.layout, own, prefabId, gone);
    return document.copyWith(
      layout: fixed.layout,
      settings: {
        ...edited.settings,
        ChangePrefabs.settingName: [
          for (final prefab in fixed.prefabs) prefab.toJson(),
        ],
      },
    );
  }

  @override
  Command undoing(Document before) =>
      InPrefab(prefabId, variant, command.undoing(_scoped(before)));

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'prefab': prefabId,
    if (variant != null) 'variant': variant,
    'command': command.toJson(),
  };
}
