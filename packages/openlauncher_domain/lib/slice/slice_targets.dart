part of 'slice_edit.dart';

/// A place nodes are kept as they are: the layout, or the tree of a prefab.
abstract class _Tree {
  Node? find(String id);

  /// The container node [id] is in; null for a root.
  Node? parentOf(String id);

  void replace(String id, Node Function(Node node) change);

  Address addressOf(String id);

  /// Puts [clip]'s node [where] node [targetId] is; the node as put, with ids
  /// that were free.
  Node insert(String targetId, Where where, NodeClip clip);

  /// Takes node [id] out; the edits that put back all it took.
  List<SliceEdit> remove(String id);
}

/// A node that is stored as it is, so any operation can change it.
class _StoredTarget extends _Target {
  _StoredTarget(this.applier, this.tree, this.id, this.address);

  final _Applier applier;
  final _Tree tree;
  final String id;
  final Address address;

  Map<String, Prefab> get _prefabs => applier.document.prefabs;

  ModuleType _type(String module) =>
      moduleNamed(module) ?? (throw CommandRefused('There is no "$module".'));

  @override
  List<SliceEdit> apply(SliceOp op) {
    final node = tree.find(id) ?? (throw const CommandRefused(_nothingThere));
    switch (op) {
      case SetField(:final module, :final field, :final value):
        if (module == sizingModule.name) {
          return _replaced(node, _sized(node, field, value));
        }
        final type = moduleNamed(module);
        return _replaced(
          node,
          node.isInstance && type != null && !type.instanceOwned
              ? withInstanceValue(node, type, field, value, _prefabs)
              : withRule(node, module, field, value),
        );
      case RevertField(:final module, :final field):
        final type = moduleNamed(module);
        return _replaced(
          node,
          node.isInstance && type != null && !type.instanceOwned
              ? withInherited(node, type, field, _prefabs)
              : withRule(node, module, field, null),
        );
      case SwitchModule(:final module, :final on):
        return _replaced(node, withSwitch(node, _type(module), on, _prefabs));
      case AddModule(:final module):
        return _replaced(node, withAdded(node, _type(module)));
      case RemoveModule(:final module):
        return _replaced(node, withRemoved(node, _type(module)));
      case SetModule(:final module, :final values):
        return _replaced(node, node.withModule(module, values));
      case SetVariant(:final variant):
        return _replaced(node, node.withVariant(variant));
      case SetOverrides(:final overrides):
        if (!node.isInstance) {
          throw const CommandRefused('That is not an instance.');
        }
        return _replaced(node, node.copyWith(overrides: overrides));
      case SetName(:final value):
        return _replaced(node, node.copyWith(name: value));
      case SetTransform(:final transform):
        return _replaced(node, node.copyWith(transform: transform));
      case Unpack():
        if (!node.isInstance) {
          throw const CommandRefused('That is not an instance.');
        }
        return _replaced(
          node,
          unpacked(node, _prefabs, {
            for (final one in applier.nodesIn(tree)) one.id,
          }),
        );
      case Place(:final rect, :final size):
        final parent = tree.parentOf(id);
        if (parent == null || parent.mode != LayoutMode.free) {
          throw const CommandRefused('Only a free layout places by position.');
        }
        return _replaced(node, placedAt(node, rect, size));
      case ReplaceNode(node: final next):
        return _replaced(node, next);
      case RemoveNode():
        return tree.remove(id);
      case Insert(:final where, :final clip):
        final inserted = tree.insert(id, where, clip);
        return [
          SliceEdit(tree.addressOf(inserted.id), const [RemoveNode()]),
        ];
    }
  }

  Node _sized(Node node, String field, Object? value) {
    final parent =
        tree.parentOf(id) ??
        (throw const CommandRefused('A screen\'s root has no size to set.'));
    return withSizing(node, parent, field, (value as num?)?.toDouble());
  }

  List<SliceEdit> _replaced(Node was, Node next) {
    tree.replace(id, (_) => next);
    return [
      SliceEdit(address, [ReplaceNode(was)]),
    ];
  }
}

/// The values an instance or a prefab's variant sets over what a node gives.
/// Only values change there: the prefab owns the modules.
abstract class _OverrideTarget extends _Target {
  _OverrideTarget(this.applier, this.address);

  final _Applier applier;
  final Address address;

  /// The id the overrides are kept under.
  String get key;

  Overrides get overrides;

  /// What the node gives where nothing is overridden.
  Node get base;

  void setOverrides(Overrides next);

  @override
  List<SliceEdit> apply(SliceOp op) => switch (op) {
    SetField(:final module, :final field, :final value) => _set(
      module,
      field,
      value,
    ),
    RevertField(:final module, :final field) => _set(module, field, null),
    SwitchModule(:final module, :final on) => _set(
      module,
      enabledKey,
      on ? null : false,
    ),
    _ => throw const CommandRefused(_overridesOnly),
  };

  List<SliceEdit> _set(String module, String field, Object? value) {
    final was =
        (jsonObject(overrides[key]?['modules'])[module]
            as Map<Object?, Object?>?)?[field];
    final given = base.modules[module]?[field];
    final kept = value == null || jsonEquals(value, given) ? null : value;
    setOverrides(withOverride(overrides, key, {field: kept}, module));
    return [
      SliceEdit(address, [SetField(module, field, was)]),
    ];
  }
}

/// A prefab's variant: the overrides it keeps for a child, or the root.
class _VariantTarget extends _OverrideTarget {
  _VariantTarget(_Applier applier, this.prefabId, this.variant, this.child)
    : super(applier, PrefabAddress(prefabId, variant: variant, child: child));

  final String prefabId, variant;
  final String? child;

  Prefab get _prefab => applier._prefab(prefabId);

  @override
  String get key => child ?? _prefab.root.id;

  @override
  Overrides get overrides =>
      (_prefab.variants[variant] ??
              (throw const CommandRefused('That variant is gone.')))
          .overrides;

  @override
  Node get base =>
      _prefab.root.all.where((node) => node.id == key).firstOrNull ??
      (throw const CommandRefused(_nothingThere));

  @override
  void setOverrides(Overrides next) {
    final prefab = _prefab;
    applier.setPrefab(
      prefab.copyWith(
        variants: {
          for (final MapEntry(:key, :value) in prefab.variants.entries)
            key: key == variant ? PrefabVariant(value.label, next) : value,
        },
      ),
    );
  }
}

/// A child of the prefab an instance shows: this instance's own overrides.
class _InstanceChildTarget extends _OverrideTarget {
  _InstanceChildTarget(_Applier applier, this.instanceId, this.child)
    : super(applier, LayoutAddress.child(instanceId, child));

  final String instanceId, child;

  Node get _instance =>
      applier.document.layout.all
          .where((node) => node.id == instanceId)
          .firstOrNull ??
      (throw const CommandRefused(_nothingThere));

  @override
  String get key => child;

  @override
  Overrides get overrides => _instance.overrides;

  @override
  Node get base {
    final instance = _instance;
    final prefab = applier._prefab(instance.prefab!);
    final shown = prefab.rootAs(prefab.variantOf(instance));
    return shown.all.where((node) => node.id == child).firstOrNull ??
        (throw const CommandRefused(_nothingThere));
  }

  @override
  void setOverrides(Overrides next) =>
      _LayoutTree(applier)
          .replace(instanceId, (node) => node.copyWith(overrides: next));
}

class _LayoutTree extends _Tree {
  _LayoutTree(this.applier);

  final _Applier applier;

  Layout get _layout => applier.document.layout;

  @override
  Node? find(String id) =>
      _layout.all.where((node) => node.id == id).firstOrNull;

  @override
  Node? parentOf(String id) => findItems(_layout, {id}).firstOrNull?.parent;

  @override
  Address addressOf(String id) => LayoutAddress(id);

  @override
  void replace(String id, Node Function(Node node) change) {
    final layout = _layout;
    final isRoot = layout.screens.any((screen) => screen.root.id == id);
    applier.setLayout(
      isRoot
          ? layout.withContainer(id, change)
          : changeItems(layout, {id}, (node, _) => change(node)),
    );
  }

  @override
  Node insert(String targetId, Where where, NodeClip clip) {
    final layout = _layout;
    final item = freshened(clip.node, layout.itemIds);
    final String containerId;
    String? before;
    if (where == Where.into) {
      if (find(targetId) == null) throw const CommandRefused(_nothingThere);
      containerId = targetId;
    } else {
      final found =
          findItems(layout, {targetId}).firstOrNull ??
          (throw const CommandRefused(_nothingThere));
      containerId = found.parent.id;
      final siblings = found.parent.children;
      final at = siblings.indexWhere((sibling) => sibling.id == targetId);
      before = where == Where.before
          ? targetId
          : at + 1 < siblings.length
          ? siblings[at + 1].id
          : null;
    }
    if (refusal(layout, item, containerId) case final reason?) {
      throw CommandRefused(reason);
    }
    applier.setLayout(
      dropItem(layout, item, Drop(containerId, before: before)),
    );
    return item;
  }

  @override
  List<SliceEdit> remove(String id) {
    final layout = _layout;
    final found =
        findItems(layout, {id}).firstOrNull ??
        (throw const CommandRefused('That cannot be removed.'));
    final after = removeItem(layout, id);
    final inside = {for (final node in found.item.all) node.id};
    final present = {for (final node in after.all) node.id};
    final lost = [
      for (final node in layout.all)
        if (node.isInstance &&
            !present.contains(node.id) &&
            !inside.contains(node.id))
          node,
    ];
    applier.setLayout(after);
    return [
      for (final node in [found.item, ...lost])
        _putBack(layout, node, cut: node.id == id),
    ];
  }

  /// The edit that puts [node] back where it was in [layout].
  SliceEdit _putBack(Layout layout, Node node, {required bool cut}) {
    final found = findItems(layout, {node.id}).first;
    final siblings = found.parent.children;
    final at = siblings.indexWhere((sibling) => sibling.id == node.id);
    final clip = NodeClip(node, cut: true);
    return at + 1 < siblings.length
        ? SliceEdit(LayoutAddress(siblings[at + 1].id), [
            Insert(Where.before, clip),
          ])
        : SliceEdit(LayoutAddress(found.parent.id), [Insert(Where.into, clip)]);
  }
}

class _PrefabTree extends _Tree {
  _PrefabTree(this.applier, this.prefabId);

  final _Applier applier;
  final String prefabId;

  Prefab get _prefab => applier._prefab(prefabId);

  @override
  Node? find(String id) =>
      _prefab.root.all.where((node) => node.id == id).firstOrNull;

  @override
  Address addressOf(String id) =>
      PrefabAddress(prefabId, child: id == _prefab.root.id ? null : id);

  @override
  void replace(String id, Node Function(Node node) change) {
    final prefab = _prefab;
    applier.setPrefab(prefab.copyWith(root: _mapped(prefab.root, id, change)));
  }

  Node _mapped(Node node, String id, Node Function(Node node) change) =>
      node.id == id
      ? change(node)
      : node.copyWith(
          children: [
            for (final child in node.children) _mapped(child, id, change),
          ],
        );

  @override
  Node? parentOf(String id) => _prefab.root.all
      .where((node) => node.children.any((child) => child.id == id))
      .firstOrNull;

  @override
  Node insert(String targetId, Where where, NodeClip clip) {
    final prefab = _prefab;
    final target =
        find(targetId) ?? (throw const CommandRefused(_nothingThere));
    final item = freshened(clip.node, {
      for (final node in prefab.root.all) node.id,
    });
    for (final part in item.all) {
      if (part.isInstance &&
          holdsPrefab(part.prefab!, prefabId, applier.document.prefabs)) {
        throw const CommandRefused('A prefab cannot contain itself.');
      }
    }
    if (where == Where.into) {
      if (!target.isContainer) {
        throw CommandRefused('"$targetId" cannot hold children.');
      }
      replace(
        targetId,
        (node) => node.copyWith(children: [...node.children, item]),
      );
      return item;
    }
    final parent =
        parentOf(targetId) ??
        (throw const CommandRefused('The root of a prefab has no siblings.'));
    replace(parent.id, (node) {
      final at = node.children.indexWhere((child) => child.id == targetId);
      return node.copyWith(
        children: [...node.children]
          ..insert(where == Where.after ? at + 1 : at, item),
      );
    });
    return item;
  }

  @override
  List<SliceEdit> remove(String id) {
    final parent =
        parentOf(id) ??
        (throw const CommandRefused('The root of a prefab cannot be removed.'));
    final at = parent.children.indexWhere((child) => child.id == id);
    final node = parent.children[at];
    final next = at + 1 < parent.children.length
        ? parent.children[at + 1]
        : null;
    replace(
      parent.id,
      (holder) => holder.copyWith(
        children: [
          for (final child in holder.children)
            if (child.id != id) child,
        ],
      ),
    );
    final clip = NodeClip(node, cut: true);
    return [
      next == null
          ? SliceEdit(addressOf(parent.id), [Insert(Where.into, clip)])
          : SliceEdit(addressOf(next.id), [Insert(Where.before, clip)]),
    ];
  }
}
