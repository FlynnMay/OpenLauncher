import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component.dart';
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
    this.template = false,
    this.card,
  });

  final String id, name;

  /// Whether new panes are made as copies of it rather than instances.
  /// One with a [card] is placed as that card; one without goes to an edge.
  final bool template;

  /// The prefab whose instance opens a pane made from this template.
  final String? card;

  /// The component. Its size is what a new instance starts with.
  final Component root;

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
  Component? instance(String entityId, {required String id}) =>
      switch (entityVar) {
        final variable? => Component.of(
          entityId,
          id: id,
          prefab: this.id,
          variable: variable,
          w: root.w,
          h: root.h,
        ),
        null => null,
      };

  /// Every non-pane descendant of the root.
  Iterable<Component> get parts =>
      root.all.skip(1).where((component) => !component.isPane);

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
  Component rootAs(String? variant) => withOverrides(
    root,
    variants[variantNamed(variant)]?.overrides ?? const {},
  );

  /// The variant [instance] uses, falling back to the first.
  String? variantOf(Component instance) =>
      variants.containsKey(instance.variant)
      ? instance.variant
      : variants.keys.firstOrNull;

  Prefab copyWith({
    String? id,
    String? name,
    Component? root,
    Map<String, PrefabVariant>? variants,
  }) => Prefab(
    id: id ?? this.id,
    name: name ?? this.name,
    root: root ?? this.root,
    variants: variants ?? this.variants,
    template: template,
    card: card,
  );

  /// Replaces the descendant [id] with what [change] returns.
  Prefab withPart(String id, Component Function(Component part) change) {
    Component walk(Component component) => component.id == id
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
          root: Component.fromJson(root),
          variants: {
            if (json['variants'] case final Map<Object?, Object?> variants)
              for (final MapEntry(:key, :value) in variants.entries)
                if (PrefabVariant.fromJson(value) case final variant?
                    when key is String)
                  key: variant,
          },
          template: json['template'] == true,
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
    if (template) 'template': true,
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
Component withOverrides(Component root, Overrides overrides) =>
    overrides.isEmpty
    ? root
    : root
          .overridden(overrides[root.id])
          .copyWith(
            children: [
              for (final child in root.children)
                withOverrides(child, overrides),
            ],
          );

/// The concrete component for [instance]: the prefab's tree with the
/// variant's overrides, then the instance's. Variables, style and triggers
/// are merged; size and position are the instance's. A missing prefab
/// leaves an empty pane in its place.
Component resolved(
  Component instance,
  Map<String, Prefab> prefabs, [
  int depth = 0,
]) {
  if (!instance.isInstance) return instance;
  final prefab = prefabs[instance.prefab];
  if (prefab == null) {
    return Component.pane(
      id: instance.id,
      w: instance.w,
      h: instance.h,
      x: instance.x,
      y: instance.y,
      flex: instance.flex,
      aspect: instance.aspect,
    );
  }
  final set = overridesOver(
    prefab.variants[prefab.variantOf(instance)]?.overrides ?? const {},
    instance.overrides,
  );
  // Child ids are prefixed with the instance id to keep them unique.
  Component part(Component child) => child
      .overridden(set[child.id])
      .copyWith(
        id: '${instance.id}/${child.id}',
        children: [for (final inner in child.children) part(inner)],
      );
  // A prefab's root may itself be an instance.
  final base = depth < Component.maxDepth
      ? resolved(prefab.root, prefabs, depth + 1)
      : prefab.root;
  final root = base.overridden(set[prefab.root.id]);
  return Component(
    id: instance.id,
    kind: root.kind,
    options: {...root.options, ...instance.options},
    vars: {
      ...root.vars,
      for (final MapEntry(:key, :value) in instance.vars.entries)
        key: value.over(root.vars[key]),
    },
    style: {...root.style, ...instance.style},
    on: {...root.on, ...instance.on},
    w: instance.w,
    h: instance.h,
    x: instance.x,
    y: instance.y,
    flex: instance.flex,
    aspect: instance.aspect,
    keep: instance.keep,
    hidden: instance.hidden,
    children: [for (final child in root.children) part(child)],
  );
}
