import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// A named set of overrides on a prefab's components.
@immutable
class PrefabVariant {
  const PrefabVariant(this.label, [this.overrides = const {}]);

  final String label;
  final Overrides overrides;

  static PrefabVariant? fromJson(Object? json) => switch (json) {
    final Map<Object?, Object?> json => PrefabVariant(switch (json['label']) {
      final String label => label,
      _ => '',
    }, overridesFromJson(json['overrides'])),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'label': label,
    if (overrides.isNotEmpty) 'overrides': overrides,
  };
}

/// A saved component, reused through instances. An instance stores only what
/// it changes, so edits to the prefab reach every instance that has not
/// overridden that value.
@immutable
class Prefab {
  const Prefab({
    required this.id,
    required this.name,
    required this.root,
    this.variants = const {},
    this.card,
  });

  final String id, name;

  /// The prefab whose instance opens an instance of this one, for one that
  /// docks and is opened from a card.
  final String? card;

  /// The component. Its size is what a new instance starts with.
  final Node root;

  /// By name; the first is the default.
  final Map<String, PrefabVariant> variants;

  Variables get vars => root.vars;
  Style get style => root.style;
  Triggers get on => root.on;

  /// The variable an entity is handed in: the root's first that holds one.
  String? get entityVar => vars.entries
      .where((entry) => entry.value.type == VarType.entity)
      .firstOrNull
      ?.key;

  /// An instance handed [entityId], at its size; null if it takes no
  /// entity.
  Node? instance(String entityId, {required String id}) => switch (entityVar) {
    final variable? => Node.of(
      entityId,
      id: id,
      prefab: this.id,
      variable: variable,
      w: root.w,
      h: root.h,
    ),
    null => null,
  };

  /// The names of the root's nodes variables: the slots an instance fills.
  Iterable<String> get slots => vars.entries
      .where((entry) => entry.value.type == VarType.nodes)
      .map((entry) => entry.key);

  /// A new instance of id [id], at its size, holding nothing in its slots.
  Node blank(String id) => Node(
    id: id,
    prefab: this.id,
    children: [
      for (final slot in slots)
        Node(
          id: slotHolderId(id, slot),
          modules: {
            slotModule.name: {'variable': slot},
          },
        ),
    ],
  ).sized(root.w, root.h);

  /// Every non-container descendant of the root.
  Iterable<Node> get parts =>
      root.all.skip(1).where((component) => !component.isContainer);

  /// The variant instances use unless they name another.
  String? get defaultVariant => variants.keys.firstOrNull;

  /// [variant] if there is one of that name, else the default.
  String? variantNamed(String? variant) =>
      variants.containsKey(variant) ? variant : defaultVariant;

  /// Whether [variant] is the tree as built: the default, with no overrides
  /// of its own.
  bool isBase(String? variant) {
    final name = variantNamed(variant);
    return name == null ||
        name == defaultVariant && variants[name]!.overrides.isEmpty;
  }

  /// The root as [variant] has it, ids unchanged.
  Node rootAs(String? variant) => withOverrides(
    root,
    variants[variantNamed(variant)]?.overrides ?? const {},
  );

  /// The variant [instance] uses, falling back to the first.
  String? variantOf(Node instance) => variants.containsKey(instance.variant)
      ? instance.variant
      : variants.keys.firstOrNull;

  Prefab copyWith({
    String? id,
    String? name,
    Node? root,
    Map<String, PrefabVariant>? variants,
  }) => Prefab(
    id: id ?? this.id,
    name: name ?? this.name,
    root: root ?? this.root,
    variants: variants ?? this.variants,
    card: card,
  );

  /// Replaces the descendant [id] with what [change] returns.
  Prefab withPart(String id, Node Function(Node part) change) {
    Node walk(Node component) => component.id == id
        ? change(component)
        : component.copyWith(
            children: [for (final child in component.children) walk(child)],
          );
    return copyWith(root: walk(root));
  }

  static final _id = RegExp(r'^([a-z0-9][a-z0-9_-]*:)?[a-z0-9]+(-[a-z0-9]+)*$');

  /// A slug, or a pack's: `<pack>:<slug>`.
  static bool validId(String id) => _id.hasMatch(id);

  static Prefab? fromJson(Object? json) {
    if (json
        case {'id': final String id, 'root': final Map<Object?, Object?> root}
        when validId(id)) {
      try {
        return Prefab(
          id: id,
          name: switch (json['name']) {
            final String name => name,
            _ => id,
          },
          root: Node.fromJson(root),
          variants: {
            if (json['variants'] case final Map<Object?, Object?> variants)
              for (final MapEntry(:key, :value) in variants.entries)
                if (PrefabVariant.fromJson(value) case final variant?
                    when key is String)
                  key: variant,
          },
          card: switch (json['card']) {
            final String card => card,
            _ => null,
          },
        );
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Skips unreadable entries and duplicate ids. Never throws.
  static List<Prefab> listFromJson(Object? json) {
    final ids = <String>{};
    return [
      if (json is List)
        for (final entry in json)
          if (Prefab.fromJson(entry) case final prefab? when ids.add(prefab.id))
            prefab,
    ];
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'card': ?card,
    'root': root.toJson(),
    if (variants.isNotEmpty)
      'variants': {
        for (final MapEntry(:key, :value) in variants.entries)
          key: value.toJson(),
      },
  };
}

/// [root]'s tree with [overrides] applied; ids are kept.
Node withOverrides(Node root, Overrides overrides) => overrides.isEmpty
    ? root
    : root
          .overridden(overrides[root.id])
          .copyWith(
            children: [
              for (final child in root.children)
                withOverrides(child, overrides),
            ],
          );

/// The concrete node for [instance]: the prefab's tree with the variant's
/// overrides, then the instance's. Its modules are merged over the prefab
/// root's, each the way its module says; where it sits is the instance's. A
/// missing prefab leaves an empty node in its place.
Node resolved(Node instance, Map<String, Prefab> prefabs, [int depth = 0]) {
  if (!instance.isInstance) return instance;
  final prefab = prefabs[instance.prefab];
  final owned = {
    for (final type in moduleTypes)
      if (type.instanceOwned) type.name,
  };
  if (prefab == null) {
    return Node(
      id: instance.id,
      transform: instance.transform,
      modules: {for (final name in owned) name: ?instance.values(name)},
    );
  }
  final set = overridesOver(
    prefab.variants[prefab.variantOf(instance)]?.overrides ?? const {},
    instance.overrides,
  );
  // What the instance puts in each slot, by its variable; the first part
  // naming one takes its nodes, after its own children.
  final slots = {
    for (final holder in instance.children)
      ?holder.slotVariable: holder.children,
  };
  Node slotted(Node part, List<Node> children) {
    final name = part.slotVariable;
    final nodes = name == null ? null : slots.remove(name);
    if (nodes == null) return part.copyWith(children: children);
    return part
        .withValue(slotModule.name, 'holder', slotHolderId(instance.id, name!))
        .copyWith(children: [...children, ...nodes]);
  }

  // Child ids are prefixed with the instance id to keep them unique.
  Node part(Node child) => slotted(
    child.overridden(set[child.id]).copyWith(id: '${instance.id}/${child.id}'),
    [for (final inner in child.children) part(inner)],
  );
  // A prefab's root may itself be an instance.
  final base = depth < Node.maxDepth
      ? resolved(prefab.root, prefabs, depth + 1)
      : prefab.root;
  final root = base.overridden(set[prefab.root.id]);
  return slotted(
    Node(
      id: instance.id,
      name: instance.name.isNotEmpty ? instance.name : root.name,
      transform: instance.transform,
      modules: {
        for (final MapEntry(key: name, :value) in root.modules.entries)
          if (!owned.contains(name)) name: value,
        for (final MapEntry(key: name, :value) in instance.modules.entries)
          name: owned.contains(name) || !root.has(name)
              ? value
              : (moduleNamed(name)?.merge ?? mergeValues)(
                  root.modules[name]!,
                  value,
                ),
      },
      hidden: instance.hidden,
    ),
    [for (final child in root.children) part(child)],
  );
}
