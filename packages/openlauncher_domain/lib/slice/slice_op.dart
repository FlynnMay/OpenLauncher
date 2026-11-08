import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/geometry.dart';
import 'package:openlauncher_domain/nodes/node.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
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
    RevertField.name => RevertField(
      jsonRequired<String>(json, 'module'),
      jsonRequired<String>(json, 'field'),
    ),
    SwitchModule.name => SwitchModule(
      jsonRequired<String>(json, 'module'),
      jsonRequired<bool>(json, 'on'),
    ),
    AddModule.name => AddModule(jsonRequired<String>(json, 'module')),
    RemoveModule.name => RemoveModule(jsonRequired<String>(json, 'module')),
    SetModule.name => SetModule(
      jsonRequired<String>(json, 'module'),
      switch (json['values']) {
        final Map<Object?, Object?> values => jsonObject(values),
        _ => null,
      },
    ),
    SetVariant.name => SetVariant(jsonOptional<String>(json, 'variant')),
    SetOverrides.name => SetOverrides(overridesFromJson(json['overrides'])),
    SetName.name => SetName(jsonOptional<String>(json, 'value') ?? ''),
    SetTransform.name => SetTransform(
      NodeTransform.fromJson(jsonObject(json['transform'])),
    ),
    Unpack.name => const Unpack(),
    Place.name => Place(
      Box.fromJson(json['rect']) ?? (throw const CommandRefused('rect')),
      Extent.fromJson(json['size']) ?? (throw const CommandRefused('size')),
    ),
    RemoveNode.name => const RemoveNode(),
    Insert.name => Insert(
      Where.values.byName(jsonRequired<String>(json, 'where')),
      Clip.fromJson(jsonObject(json['clip'])) as NodeClip,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      rect: Box.fromJson(json['rect']),
      size: Extent.fromJson(json['size']),
    ),
    SetSetting.name => SetSetting(
      jsonRequired<String>(json, 'key'),
      json['value'],
    ),
    SetEntry.name => SetEntry(
      jsonRequired<String>(json, 'key'),
      jsonRequired<String>(json, 'entry'),
      json['value'],
    ),
    AddScreen.name => AddScreen(
      id: jsonOptional<String>(json, 'id'),
      label: jsonOptional<String>(json, 'screenName') ?? '',
    ),
    RestoreScreen.name => RestoreScreen(
      Screen.fromJson(jsonRequired<Map<Object?, Object?>>(json, 'screen')),
      jsonOptional<int>(json, 'index') ?? 0,
    ),
    SetStartup.name => SetStartup(
      screenId: jsonOptional<String>(json, 'screen'),
      remember: jsonOptional<bool>(json, 'remember'),
    ),
    SetLayout.name => SetLayout(Layout.fromJson(jsonObject(json['layout']))),
    ResetLayout.name => const ResetLayout(),
    RenameScreen.name => RenameScreen(
      jsonOptional<String>(json, 'screenName') ?? '',
    ),
    RemoveScreen.name => const RemoveScreen(),
    DuplicateScreen.name => const DuplicateScreen(),
    SetRemoved.name => SetRemoved({
      for (final id in jsonRequired<List<Object?>>(json, 'ids')) id! as String,
    }),
    SetInbox.name => SetInbox(jsonRequired<String>(json, 'container')),
    SavePrefab.name => SavePrefab(
      Prefab.fromJson(json['prefab']) ??
          (throw const CommandRefused('That is not a prefab.')),
    ),
    RevertPrefab.name => const RevertPrefab(),
    DeletePrefab.name => const DeletePrefab(),
    RenameChild.name => RenameChild(jsonRequired<String>(json, 'to')),
    MakePrefab.name => MakePrefab(
      jsonRequired<String>(json, 'prefab'),
      jsonRequired<String>(json, 'prefabName'),
      size: Extent.fromJson(json['size']),
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

/// Hands [field] of [module] back to what the prefab gives; on a node that is
/// not an instance, takes the value away.
class RevertField extends SliceOp {
  const RevertField(this.module, this.field);

  static const name = 'revert';

  final String module, field;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'module': module,
    'field': field,
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

/// Puts [values] as the whole of a module's values; null takes the module
/// off. For a value that is more than one field, such as variables or triggers.
class SetModule extends SliceOp {
  const SetModule(this.module, this.values);

  static const name = 'setModule';

  final String module;
  final ModuleValues? values;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'module': module,
    'values': values,
  };
}

/// Makes an instance show another variant of its prefab; null the first.
class SetVariant extends SliceOp {
  const SetVariant(this.variant);

  static const name = 'setVariant';

  final String? variant;

  @override
  Map<String, Object?> toJson() => {'op': name, 'variant': variant};
}

/// An instance's own differences from its prefab, all at once; none puts it
/// back to what the prefab gives.
class SetOverrides extends SliceOp {
  const SetOverrides(this.overrides);

  static const name = 'setOverrides';

  final Overrides overrides;

  @override
  Map<String, Object?> toJson() => {'op': name, 'overrides': overrides};
}

/// Names the node; empty takes the name away.
class SetName extends SliceOp {
  const SetName(this.value);

  static const name = 'setName';

  final String value;

  @override
  Map<String, Object?> toJson() => {'op': name, 'value': value};
}

/// Where the node sits in a parent that does not lay it out.
class SetTransform extends SliceOp {
  const SetTransform(this.transform);

  static const name = 'setTransform';

  final NodeTransform transform;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'transform': transform.toJson(),
  };
}

/// Turns an instance into plain nodes, as its prefab shows it.
class Unpack extends SliceOp {
  const Unpack();

  static const name = 'unpack';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// Moves a node of a free container to cover [rect] of it, which is [size] big.
class Place extends SliceOp {
  const Place(this.rect, this.size);

  static const name = 'place';

  final Box rect;
  final Extent size;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'rect': rect.toJson(),
    'size': size.toJson(),
  };
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

/// Puts the node of [clip] [where] the slice's node is. In a grid it takes
/// the cell ([x], [y]) if given; in a free layout it covers [rect] of a parent
/// that is [size] big.
class Insert extends SliceOp {
  const Insert(this.where, this.clip, {this.x, this.y, this.rect, this.size});

  static const name = 'insert';

  final Where where;
  final NodeClip clip;
  final double? x, y;
  final Box? rect;
  final Extent? size;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'where': where.name,
    'clip': clip.toJson(),
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (rect != null) 'rect': rect!.toJson(),
    if (size != null) 'size': size!.toJson(),
  };
}

/// At `/`: sets a setting to a whole new value.
class SetSetting extends SliceOp {
  const SetSetting(this.key, this.value);

  static const name = 'setSetting';

  final String key;
  final Object? value;

  @override
  Map<String, Object?> toJson() => {'op': name, 'key': key, 'value': value};
}

/// At `/`: sets one entry of a setting that is a map, such as one app's name;
/// null takes the entry away.
class SetEntry extends SliceOp {
  const SetEntry(this.key, this.entry, this.value);

  static const name = 'setEntry';

  final String key, entry;
  final Object? value;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'key': key,
    'entry': entry,
    'value': value,
  };
}

/// At `/`: an empty screen. [id] is wanted, not promised; [name] is its label.
class AddScreen extends SliceOp {
  const AddScreen({this.id, this.label = ''});

  static const name = 'addScreen';

  final String? id;
  final String label;

  /// The id the screen gets in [layout].
  String idIn(Layout layout) =>
      freeId(id ?? slugOf(label, 'screen'), layout.itemIds);

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    if (id != null) 'id': id,
    'screenName': label,
  };
}

/// At `/`: a screen put back as it was, at place [index] among the screens.
class RestoreScreen extends SliceOp {
  const RestoreScreen(this.screen, this.index);

  static const name = 'restoreScreen';

  final Screen screen;
  final int index;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'screen': screen.toJson(),
    'index': index,
  };
}

/// At `/`: which screen the launcher opens on, and whether it opens on the one
/// shown last instead. A value left out stays as it is.
class SetStartup extends SliceOp {
  const SetStartup({this.screenId, this.remember});

  static const name = 'setStartup';

  final String? screenId;
  final bool? remember;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    if (screenId != null) 'screen': screenId,
    if (remember != null) 'remember': remember,
  };
}

/// At `/`: puts a whole layout in as the user's own.
class SetLayout extends SliceOp {
  const SetLayout(this.layout);

  static const name = 'setLayout';

  final Layout layout;

  @override
  Map<String, Object?> toJson() => {'op': name, 'layout': layout.toJson()};
}

/// At `/`: goes back to the layout the pack starts with, dropping the user's.
class ResetLayout extends SliceOp {
  const ResetLayout();

  static const name = 'resetLayout';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// At `screen:<id>`: gives the screen another label.
class RenameScreen extends SliceOp {
  const RenameScreen(this.label);

  static const name = 'renameScreen';

  final String label;

  @override
  Map<String, Object?> toJson() => {'op': name, 'screenName': label};
}

/// At `screen:<id>`: takes the screen away; the last one stays.
class RemoveScreen extends SliceOp {
  const RemoveScreen();

  static const name = 'removeScreen';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// At `screen:<id>`: a copy of the screen next to it, with new nodes. Pictures
/// set on a node go with its copy.
class DuplicateScreen extends SliceOp {
  const DuplicateScreen();

  static const name = 'duplicateScreen';

  /// The id the copy of screen [id] gets in [layout].
  static String copyIdIn(Layout layout, String id) =>
      freeId(id, layout.itemIds);

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// At `/`: the apps the user took off the screens, which are not put back.
class SetRemoved extends SliceOp {
  const SetRemoved(this.ids);

  static const name = 'setRemoved';

  final Set<String> ids;

  @override
  Map<String, Object?> toJson() => {'op': name, 'ids': ids.toList()..sort()};
}

/// At `/`: the container new apps arrive in.
class SetInbox extends SliceOp {
  const SetInbox(this.containerId);

  static const name = 'setInbox';

  final String containerId;

  @override
  Map<String, Object?> toJson() => {'op': name, 'container': containerId};
}

/// At `prefab:<id>`: saves the whole prefab as the user's, new or not.
class SavePrefab extends SliceOp {
  const SavePrefab(this.prefab);

  static const name = 'savePrefab';

  final Prefab prefab;

  @override
  Map<String, Object?> toJson() => {'op': name, 'prefab': prefab.toJson()};
}

/// At `prefab:<id>`: takes away the user's own copy, so the pack's shows.
class RevertPrefab extends SliceOp {
  const RevertPrefab();

  static const name = 'revertPrefab';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// At `prefab:<id>`: deletes the user's prefab, and unpacks its instances
/// where they stand.
class DeletePrefab extends SliceOp {
  const DeletePrefab();

  static const name = 'deletePrefab';

  @override
  Map<String, Object?> toJson() => {'op': name};
}

/// At `prefab:<id>/<child>`: calls the child [to] instead, and everything that
/// names it.
class RenameChild extends SliceOp {
  const RenameChild(this.to);

  static const name = 'renameChild';

  final String to;

  @override
  Map<String, Object?> toJson() => {'op': name, 'to': to};
}

/// Makes a prefab of the node and its contents, which an instance replaces.
/// [size] is what a node placed by its transform is drawn at.
class MakePrefab extends SliceOp {
  const MakePrefab(this.prefabId, this.prefabName, {this.size});

  static const name = 'makePrefab';

  final String prefabId, prefabName;
  final Extent? size;

  @override
  Map<String, Object?> toJson() => {
    'op': name,
    'prefab': prefabId,
    'prefabName': prefabName,
    if (size != null) 'size': size!.toJson(),
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
