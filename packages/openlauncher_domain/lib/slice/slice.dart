import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/slice/address.dart';
import 'package:openlauncher_domain/slice/clip.dart';
import 'package:openlauncher_domain/slice/slice_edit.dart';
import 'package:openlauncher_domain/slice/slice_op.dart';

export 'package:openlauncher_domain/slice/address.dart';
export 'package:openlauncher_domain/slice/clip.dart';
export 'package:openlauncher_domain/slice/slice_edit.dart';
export 'package:openlauncher_domain/slice/slice_op.dart';

/// One part of the config, loaded by [address], to look at and change. Each
/// change is done to the slice's own copy at once and kept as an operation;
/// [save] hands back those operations as a [SliceEdit] to send. Nothing else
/// in the config is read or written.
class Slice {
  Slice._(this.address, this._work);

  /// Loads what [address] points at in [document]. Throws [CommandRefused] if
  /// there is nothing there.
  factory Slice.load(Document document, Object address) {
    final slice = Slice._(
      address is Address ? address : Address.parse('$address'),
      document,
    );
    slice.node;
    return slice;
  }

  final Address address;
  Document _work;
  final _ops = <SliceOp>[];

  /// The slice's copy of the config, with the changes made so far.
  Document get document => _work;

  /// The node as the address shows it: an instance's child as that instance
  /// draws it, a prefab's child as its variant has it.
  Node get node => switch (address) {
    ConfigAddress() ||
    ScreenAddress() => throw const CommandRefused('There is no node there.'),
    PrefabAddress(:final prefabId, :final variant, :final child) => _inPrefab(
      prefabId,
      variant,
      child,
    ),
    LayoutAddress() => _inLayout(address as LayoutAddress),
  };

  Node _inPrefab(String id, String? variant, String? child) {
    final prefab =
        _work.prefabs[id] ??
        (throw const CommandRefused('That prefab is gone.'));
    final shown = variant == null ? prefab.root : prefab.rootAs(variant);
    return shown.all
            .where((node) => node.id == (child ?? prefab.root.id))
            .firstOrNull ??
        (throw const CommandRefused('There is nothing there.'));
  }

  Node _inLayout(LayoutAddress at) {
    final nodes = {for (final node in _work.layout.all) node.id: node};
    if (nodes[at.path] case final node?) return node;
    for (
      var cut = at.path.lastIndexOf('/');
      cut > 0;
      cut = at.path.lastIndexOf('/', cut - 1)
    ) {
      final owner = nodes[at.path.substring(0, cut)];
      if (owner != null && owner.isInstance) {
        final shown = resolved(owner, _work.prefabs);
        final wanted = '${owner.id}/${at.path.substring(cut + 1)}';
        return shown.all.where((node) => node.id == wanted).firstOrNull ??
            (throw const CommandRefused('There is nothing there.'));
      }
    }
    throw const CommandRefused('There is nothing there.');
  }

  Slice _do(SliceOp op) {
    _work = SliceEdit(address, [op]).apply(_work).document;
    _ops.add(op);
    return this;
  }

  /// Sets [field] of [module]; null reverts it to what it would be without.
  Slice edit(String module, String field, Object? value) =>
      _do(SetField(module, field, value));

  Slice revert(String module, String field) => _do(RevertField(module, field));

  Slice switchModule(String module, {required bool on}) =>
      _do(SwitchModule(module, on));

  Slice addModule(String module) => _do(AddModule(module));

  Slice removeModule(String module) => _do(RemoveModule(module));

  /// The node and all it holds, as a value; nothing changes.
  Clip copy() => NodeClip(_stored());

  /// The node and all it holds, taken out of its place.
  Clip cut() {
    final clip = NodeClip(_stored(), cut: true);
    _do(const RemoveNode());
    return clip;
  }

  /// The values of one module of the node as the address shows it.
  ModuleClip copyModule(String module) =>
      ModuleClip(module, {...?node.modules[module]});

  Slice pasteAfter(Clip clip) => _do(Insert(Where.after, _nodeClip(clip)));

  Slice pasteBefore(Clip clip) => _do(Insert(Where.before, _nodeClip(clip)));

  Slice pasteInto(Clip clip) => _do(Insert(Where.into, _nodeClip(clip)));

  Slice pasteModule(Clip clip) {
    if (clip is! ModuleClip) {
      throw const CommandRefused('That is not a module.');
    }
    return setModule(clip.module, clip.values);
  }

  /// Puts [values] as all of a module's values; null takes the module off.
  Slice setModule(String module, ModuleValues? values) =>
      _do(SetModule(module, values));

  /// Makes an instance show another variant of its prefab.
  Slice setVariant(String? variant) => _do(SetVariant(variant));

  Slice rename(String name) => _do(SetName(name));

  Slice setTransform(NodeTransform transform) => _do(SetTransform(transform));

  /// Turns an instance into plain nodes.
  Slice unpack() => _do(const Unpack());

  /// Moves a node of a free container to cover [rect] of it, [size] big.
  Slice place(Box rect, Extent size) => _do(Place(rect, size));

  /// Sets one Sizing field; null clears it.
  Slice size(String field, double? value) =>
      edit(sizingModule.name, field, value);

  /// Changes the node by [how], as the module values that come out different.
  /// For editors that work out a whole node at a time.
  Slice change(Node Function(Node node) how) {
    moduleOpsBetween(node, how(node)).forEach(_do);
    return this;
  }

  NodeClip _nodeClip(Clip clip) => clip is NodeClip
      ? clip
      : throw const CommandRefused('That is not a node.');

  /// The node as stored. An instance's child is not stored, only the
  /// instance's overrides of it, so it cannot be lifted out.
  Node _stored() => switch (address) {
    LayoutAddress(:final path)
        when !_work.layout.all.any((node) => node.id == path) =>
      throw const CommandRefused(
        'A child of a prefab belongs to the prefab, so it cannot be moved.',
      ),
    PrefabAddress(variant: != null) => throw const CommandRefused(
      'A variant only overrides values; its nodes belong to the prefab.',
    ),
    _ => node,
  };

  /// What was done, to send.
  SliceEdit save() => SliceEdit(address, List.unmodifiable(_ops));
}

/// The operations that turn [before]'s modules into [after]'s: each module
/// whose values differ is set whole, or taken off.
List<SliceOp> moduleOpsBetween(Node before, Node after) => [
  for (final module in {...before.modules.keys, ...after.modules.keys})
    if (!jsonEquals(before.modules[module], after.modules[module]))
      SetModule(module, after.modules[module]),
];
