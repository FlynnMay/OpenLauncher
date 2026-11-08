import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/slice/clip.dart';

/// One instruction on how to change what an address points at.
sealed class SliceOp {
  const SliceOp();

  factory SliceOp.fromJson(Json json) => switch (json['op']) {
    SetField.name => SetField(
      jsonRequired<String>(json, 'module'),
      jsonRequired<String>(json, 'field'),
      json['value'],
    ),
    SwitchModule.name => SwitchModule(
      jsonRequired<String>(json, 'module'),
      jsonRequired<bool>(json, 'on'),
    ),
    AddModule.name => AddModule(jsonRequired<String>(json, 'module')),
    RemoveModule.name => RemoveModule(jsonRequired<String>(json, 'module')),
    PasteModule.name => PasteModule(
      Clip.fromJson(jsonObject(json['clip'])) as ModuleClip,
    ),
    RemoveNode.name => const RemoveNode(),
    Insert.name => Insert(
      Where.values.byName(jsonRequired<String>(json, 'where')),
      Clip.fromJson(jsonObject(json['clip'])) as NodeClip,
    ),
    ReplaceNode.name => ReplaceNode(
      Node.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'node')),
    ),
    _ => throw CommandRefused('"${json['op']}" is not an operation.'),
  };

  Map<String, Object?> toJson();
}

/// Sets [field] of [module]; null puts back what it would be without it, which
/// for an instance's child is what the prefab gives.
class SetField extends SliceOp {
  const SetField(this.module, this.field, this.value);

  static const name = 'set';

  final String module, field;
  final Object? value;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'module': module,
    'field': field,
    'value': value,
  };
}

/// Switches a module on or off, keeping its values.
class SwitchModule extends SliceOp {
  const SwitchModule(this.module, this.on);

  static const name = 'switch';

  final String module;
  final bool on;

  @override
  Map<String, Object?> toJson() => {'op': name, 'module': module, 'on': on};
}

/// Adds a module, and the modules it needs.
class AddModule extends SliceOp {
  const AddModule(this.module);

  static const name = 'addModule';

  final String module;

  @override
  Map<String, Object?> toJson() => {'op': name, 'module': module};
}

/// Takes a module away.
class RemoveModule extends SliceOp {
  const RemoveModule(this.module);

  static const name = 'removeModule';

  final String module;

  @override
  Map<String, Object?> toJson() => {'op': name, 'module': module};
}

/// Puts a copied module's values on the node, in place of its own.
class PasteModule extends SliceOp {
  const PasteModule(this.clip);

  static const name = 'pasteModule';

  final ModuleClip clip;

  @override
  Map<String, Object?> toJson() => {'op': name, 'clip': clip.toJson()};
}

/// Takes the node, and what it holds, out.
class RemoveNode extends SliceOp {
  const RemoveNode();

  static const name = 'remove';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// Where a pasted node goes, from the node the slice is loaded at.
enum Where { after, before, into }

/// Puts the node of [clip] [where] the slice's node is.
class Insert extends SliceOp {
  const Insert(this.where, this.clip);

  static const name = 'insert';

  final Where where;
  final NodeClip clip;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'where': where.name,
    'clip': clip.toJson(),
  };
}

/// Puts [node] in place of the one at the address, as the undo of an edit
/// that changed it in ways one field cannot say.
class ReplaceNode extends SliceOp {
  const ReplaceNode(this.node);

  static const name = 'replace';

  final Node node;

  @override
  Map<String, Object?> toJson() => {'op': name, 'node': node.toJson()};
}
