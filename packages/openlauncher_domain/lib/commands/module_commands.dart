import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/commands/node_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/editing/module_edit.dart';
import 'package:openlauncher_domain/editing/prefab_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

const _nothingThere = 'There is nothing there to change.';

/// An edit to nodes that depends on the prefabs in use, which the layout does
/// not hold. Its undo is the patch that puts back what it changed.
abstract class PrefabAwareEdit extends Command {
  const PrefabAwareEdit();

  /// The layout once this is done, given the prefabs in use. Throws
  /// [CommandRefused] if it cannot be.
  Layout applyUsing(Layout layout, Map<String, Prefab> prefabs);

  @override
  Document edit(Document document) =>
      document.copyWith(layout: applyUsing(document.layout, document.prefabs));

  @override
  Command undoing(Document before) => PatchLayout.turning(
    applyUsing(before.layout, before.prefabs),
    before.layout,
  );
}

/// An edit to the module [module] of nodes [ids].
abstract class ModuleCommand extends PrefabAwareEdit {
  const ModuleCommand(this.ids, this.module);

  final Set<String> ids;
  final String module;

  ModuleType get moduleType =>
      moduleNamed(module) ?? (throw CommandRefused('No module "$module".'));

  /// [node] with this edit done.
  Node editNode(Node node, Map<String, Prefab> prefabs);

  @override
  Layout applyUsing(Layout layout, Map<String, Prefab> prefabs) {
    if (findItems(layout, ids).isEmpty) {
      throw const CommandRefused(_nothingThere);
    }
    return changeItems(layout, ids, (node, _) => editNode(node, prefabs));
  }

  Map<String, Object?> get _base => {
    'type': type,
    'ids': ids.toList()..sort(),
    'module': module,
  };

  static Set<String> idsIn(Json json) => {
    for (final id in jsonRequired<List<Object?>>(json, 'ids')) id! as String,
  };
}

/// Sets [key] of a module on nodes: an instance's over its prefab's.
class SetModuleValue extends ModuleCommand {
  const SetModuleValue(super.ids, super.module, this.key, this.value);

  factory SetModuleValue.fromJson(Json json) => SetModuleValue(
    ModuleCommand.idsIn(json),
    jsonRequired<String>(json, 'module'),
    jsonRequired<String>(json, 'key'),
    json['value'],
  );

  static const typeName = 'module.set';

  final String key;
  final Object? value;

  @override
  String get type => typeName;

  @override
  Node editNode(Node node, Map<String, Prefab> prefabs) =>
      node.isInstance && !moduleType.instanceOwned
      ? withInstanceValue(node, moduleType, key, value, prefabs)
      : withRule(node, module, key, value);

  @override
  Map<String, Object?> toJson() => {..._base, 'key': key, 'value': value};
}

/// Takes an instance's own [keys] of a module away, so its prefab's shows.
class RevertModuleValue extends ModuleCommand {
  const RevertModuleValue(super.ids, super.module, this.keys);

  factory RevertModuleValue.fromJson(Json json) => RevertModuleValue(
    ModuleCommand.idsIn(json),
    jsonRequired<String>(json, 'module'),
    [
      for (final key in jsonRequired<List<Object?>>(json, 'keys'))
        key! as String,
    ],
  );

  static const typeName = 'module.revert';

  final List<String> keys;

  @override
  String get type => typeName;

  @override
  Node editNode(Node node, Map<String, Prefab> prefabs) => keys.fold(
    node,
    (next, key) => withInherited(next, moduleType, key, prefabs),
  );

  @override
  Map<String, Object?> toJson() => {..._base, 'keys': keys};
}

/// Switches a module on or off on nodes.
class SwitchModule extends ModuleCommand {
  const SwitchModule(super.ids, super.module, this.on);

  factory SwitchModule.fromJson(Json json) => SwitchModule(
    ModuleCommand.idsIn(json),
    jsonRequired<String>(json, 'module'),
    jsonRequired<bool>(json, 'on'),
  );

  static const typeName = 'module.switch';

  final bool on;

  @override
  String get type => typeName;

  @override
  Node editNode(Node node, Map<String, Prefab> prefabs) =>
      withSwitch(node, moduleType, on, prefabs);

  @override
  Map<String, Object?> toJson() => {..._base, 'on': on};
}

/// Adds a module, and the modules it needs, to nodes.
class AddModule extends ModuleCommand {
  const AddModule(super.ids, super.module);

  factory AddModule.fromJson(Json json) => AddModule(
    ModuleCommand.idsIn(json),
    jsonRequired<String>(json, 'module'),
  );

  static const typeName = 'module.add';

  @override
  String get type => typeName;

  @override
  Node editNode(Node node, Map<String, Prefab> prefabs) =>
      withAdded(node, moduleType);

  @override
  Map<String, Object?> toJson() => _base;
}

/// Takes a module off nodes.
class RemoveModule extends ModuleCommand {
  const RemoveModule(super.ids, super.module);

  factory RemoveModule.fromJson(Json json) => RemoveModule(
    ModuleCommand.idsIn(json),
    jsonRequired<String>(json, 'module'),
  );

  static const typeName = 'module.remove';

  @override
  String get type => typeName;

  @override
  Node editNode(Node node, Map<String, Prefab> prefabs) =>
      withRemoved(node, moduleType);

  @override
  Map<String, Object?> toJson() => _base;
}

/// Turns an instance into plain nodes, as its prefab shows it.
class UnpackInstance extends PrefabAwareEdit {
  const UnpackInstance(this.id);

  factory UnpackInstance.fromJson(Json json) =>
      UnpackInstance(jsonRequired<String>(json, 'id'));

  static const typeName = 'node.unpack';

  final String id;

  @override
  String get type => typeName;

  @override
  Layout applyUsing(Layout layout, Map<String, Prefab> prefabs) {
    if (layout.node(id)?.isInstance != true) {
      throw const CommandRefused('That is not an instance.');
    }
    return withUnpacked(layout, id, prefabs);
  }

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id};
}

/// The commands that depend on prefabs, by the name they go by in JSON.
final Map<String, CommandReader> moduleCommandReaders = {
  SetModuleValue.typeName: SetModuleValue.fromJson,
  RevertModuleValue.typeName: RevertModuleValue.fromJson,
  SwitchModule.typeName: SwitchModule.fromJson,
  AddModule.typeName: AddModule.fromJson,
  RemoveModule.typeName: RemoveModule.fromJson,
  UnpackInstance.typeName: UnpackInstance.fromJson,
};
