import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/commands/prefab_commands.dart';
import 'package:openlauncher_domain/editing/layout_edit.dart';
import 'package:openlauncher_domain/editing/module_edit.dart';
import 'package:openlauncher_domain/editing/prefab_edit.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_enums.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/slice/address.dart';
import 'package:openlauncher_domain/slice/clip.dart';
import 'package:openlauncher_domain/slice/slice_op.dart';
import 'package:openlauncher_domain/validation/validation.dart';

part 'slice_targets.dart';

/// What applying an edit leaves: the document, and the edits that undo it,
/// in the order to apply them.
typedef SliceResult = ({Document document, List<SliceEdit> inverse});

/// Operations on one address, as data. The same code applies them wherever
/// they are sent: the editor to see the result, the TV to keep it.
class SliceEdit {
  const SliceEdit(this.address, this.ops);

  factory SliceEdit.fromJson(Json json) =>
      SliceEdit(Address.parse(jsonRequired<String>(json, 'address')), [
        for (final op in jsonRequired<List<Object?>>(json, 'ops'))
          SliceOp.fromJson(jsonObject(op)),
      ]);

  final Address address;
  final List<SliceOp> ops;

  /// [document] with the operations done, and the edits that undo them.
  /// Throws [CommandRefused] if they cannot be done, or leave the layout
  /// broken in a way it was not.
  SliceResult apply(Document document) {
    final applier = _Applier(document);
    for (final op in ops) {
      applier.run(address, op);
    }
    final added = const LayoutValidator().problemsAdded(
      before: document.layout,
      after: applier.document.layout,
    );
    if (added.isNotEmpty) throw CommandRefused(added.first.message);
    return (document: applier.document, inverse: applier.inverse);
  }

  Map<String, Object?> toJson() => {
    'address': address.toString(),
    'ops': [for (final op in ops) op.toJson()],
  };
}

const _nothingThere = 'There is nothing there to change.';
const _overridesOnly =
    'Only values can be changed there, since the prefab owns its modules.';

/// Does operations one at a time to a document, keeping what undoes them.
class _Applier {
  _Applier(this.document);

  Document document;

  /// In the order to apply: the undo of the last operation is first.
  final inverse = <SliceEdit>[];

  void run(Address address, SliceOp op) {
    final target = _targetFor(address);
    final undo = target.apply(op);
    inverse.insertAll(0, undo);
  }

  _Target _targetFor(Address address) => switch (address) {
    ConfigAddress() => throw const CommandRefused(
      'Settings are not edited through a slice yet.',
    ),
    PrefabAddress(:final prefabId, :final variant, :final child) =>
      variant == null
          ? _StoredTarget(
              this,
              _PrefabTree(this, prefabId),
              child ?? _prefab(prefabId).root.id,
              address,
            )
          : _VariantTarget(this, prefabId, variant, child),
    LayoutAddress() => _layoutTarget(address),
  };

  Prefab _prefab(String id) =>
      document.prefabs[id] ??
      (throw const CommandRefused('That prefab is gone.'));

  _Target _layoutTarget(LayoutAddress address) {
    final nodes = {for (final node in document.layout.all) node.id: node};
    final path = address.path;
    if (nodes.containsKey(path)) {
      return _StoredTarget(this, _LayoutTree(this), path, address);
    }
    for (
      var cut = path.lastIndexOf('/');
      cut > 0;
      cut = path.lastIndexOf('/', cut - 1)
    ) {
      final owner = nodes[path.substring(0, cut)];
      if (owner != null && owner.isInstance) {
        return _InstanceChildTarget(this, owner.id, path.substring(cut + 1));
      }
    }
    throw const CommandRefused(_nothingThere);
  }

  /// Sets the user's [prefab], and what every later operation sees of it.
  void setPrefab(Prefab prefab) {
    final own = withPrefab(
      Prefab.listFromJson(document.settings[ChangePrefabs.settingName]),
      prefab,
    );
    document = document.copyWith(
      settings: {
        ...document.settings,
        ChangePrefabs.settingName: [for (final one in own) one.toJson()],
      },
      prefabs: {...document.prefabs, prefab.id: prefab},
    );
  }

  /// Every node of the tree an operation is in, for ids that must stay free.
  Iterable<Node> nodesIn(_Tree tree) =>
      tree is _PrefabTree ? tree._prefab.root.all : document.layout.all;

  void setLayout(Layout layout) => document = document.copyWith(layout: layout);
}

/// What an address points at, and how each operation changes it.
abstract class _Target {
  /// Does [op]; the edits that undo it.
  List<SliceEdit> apply(SliceOp op);
}

/// [node] with ids that are free among [used], which they are added to: the
/// ids it has where they are free, else suffixed. An instance's holders go by
/// its id.
Node freshened(Node node, Set<String> used) {
  final id = freeId(node.id, used);
  used.add(id);
  if (node.isInstance) {
    return node.copyWith(
      id: id,
      children: [
        for (final holder in node.children) _holderFreshened(holder, id, used),
      ],
    );
  }
  return node.copyWith(
    id: id,
    children: [for (final child in node.children) freshened(child, used)],
  );
}

Node _holderFreshened(Node holder, String instanceId, Set<String> used) {
  final id = switch (holder.slotVariable) {
    final variable? => slotHolderId(instanceId, variable),
    null => holder.id,
  };
  used.add(id);
  return holder.copyWith(
    id: id,
    children: [for (final child in holder.children) freshened(child, used)],
  );
}
