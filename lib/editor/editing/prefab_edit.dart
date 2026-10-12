import 'dart:convert';

import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// The pane a prefab's root sits in while it is edited as a layout.
const prefabStageId = 'prefab/stage';

/// [prefab] as a layout the editing tools work on: its root, as [variant]
/// has it, alone in a pane, whose rows are [rowHeight] high if given.
Layout prefabAsLayout(Prefab prefab, [String? variant, double? rowHeight]) =>
    Layout(
      inbox: prefab.root.id,
      layers: [
        Layer(
          id: Layout.homeId,
          root: Component.pane(
            id: prefabStageId,
            columns: Component.globalColumns,
            rules: {'rowHeight': ?rowHeight},
            children: [prefab.rootAs(variant)],
          ),
        ),
      ],
    );

/// The prefab's root in a layout made by [prefabAsLayout], if still there.
Component? prefabRootIn(Layout layout, String rootId) =>
    layout.home.root.children.where((child) => child.id == rootId).firstOrNull;

Component _everywhere(
  Component component,
  Component Function(Component component) change,
) => change(
  component.copyWith(
    children: [
      for (final child in component.children) _everywhere(child, change),
    ],
  ),
);

/// [layout] with [change] applied to every component, innermost first.
Layout _throughout(
  Layout layout,
  Component Function(Component component) change,
) => layout.copyWith(
  layers: [
    for (final layer in layout.layers)
      layer.withRoot(_everywhere(layer.root, change)),
  ],
);

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// What a component is apart from what an override can change.
String _shape(Component component, {required bool root}) {
  final json = component.sized(component.w, component.h).toJson()
    ..remove('options')
    ..remove('style')
    ..remove('hidden')
    ..remove('children');
  // A root's size is the prefab's, not a variant's.
  if (!root) json.remove('transform');
  return jsonEncode(json);
}

Map<String, Object?> _changed(
  Map<String, Object?> was,
  Map<String, Object?> now,
  Object? Function(String key) unset,
) => {
  for (final key in {...was.keys, ...now.keys})
    if (!_same(was[key], now[key])) key: now[key] ?? unset(key),
};

/// What [edited] changes in [base]'s tree, as overrides. Null if they differ
/// in what overrides cannot hold: children, variables, triggers, kind.
Overrides? overridesBetween(Component base, Component edited) {
  final result = <String, Map<String, Object?>>{};
  bool walk(Component was, Component now, {required bool root}) {
    if (_shape(was, root: root) != _shape(now, root: root) ||
        was.children.length != now.children.length) {
      return false;
    }
    final described = ComponentRegistry.named(was.kind)?.options ?? const [];
    final options = _changed(
      was.options,
      now.options,
      // An override cannot remove; the default says the same.
      (key) =>
          described
              .where((option) => option.key == key)
              .firstOrNull
              ?.defaultValue ??
          '',
    );
    final style = _changed(was.style, now.style, (_) => null);
    final transform = root
        ? const <String, Object?>{}
        : {
            if (was.w != now.w) 'w': now.w,
            if (was.h != now.h) 'h': now.h,
            if (now.x case final x? when was.x != x) 'x': x,
            if (now.y case final y? when was.y != y) 'y': y,
            // 0 means none.
            if (was.flex != now.flex) 'flex': now.flex ?? 0,
            if (was.aspect != now.aspect) 'aspect': now.aspect ?? 0,
            if (was.keep != now.keep) 'keep': now.keep,
          };
    final set = {
      if (options.isNotEmpty) 'options': options,
      if (style.isNotEmpty) 'style': style,
      if (transform.isNotEmpty) 'transform': transform,
      if (was.hidden != now.hidden) 'hidden': now.hidden,
    };
    if (set.isNotEmpty) result[was.id] = set;
    for (final (index, child) in was.children.indexed) {
      if (!walk(child, now.children[index], root: false)) return false;
    }
    return true;
  }

  return walk(base, edited, root: true) ? result : null;
}

/// [prefab] after its tree, shown as [variant], was edited to [root]. Edits
/// under a variant that is not the base become that variant's overrides;
/// null if they are not ones a variant can hold.
Prefab? withEdited(Prefab prefab, String? variant, Component root) {
  if (prefab.isBase(variant)) {
    return prefab.copyWith(root: root.sized(root.w, root.h));
  }
  final name = prefab.variantNamed(variant)!;
  final overrides = overridesBetween(prefab.root, root);
  if (overrides == null) return null;
  return prefab.copyWith(
    variants: {
      for (final MapEntry(:key, :value) in prefab.variants.entries)
        key: key == name ? PrefabVariant(value.label, overrides) : value,
    },
  );
}

Overrides _rekeyed(Overrides overrides, Map<String, String?> ids) => {
  for (final MapEntry(:key, :value) in overrides.entries)
    if (!ids.containsKey(key)) key: value else ?ids[key]: value,
};

/// [layout] and [prefabs] with the overrides naming [prefabId]'s children
/// re-keyed by [ids] (old to new; null drops them): in its variants, its
/// instances and panes' rules for it.
({Layout layout, List<Prefab> prefabs}) withPartIds(
  Layout layout,
  List<Prefab> prefabs,
  String prefabId,
  Map<String, String?> ids,
) {
  Component fix(Component component) {
    var fixed = component;
    if (component.prefab == prefabId && component.overrides.isNotEmpty) {
      fixed = fixed.copyWith(overrides: _rekeyed(component.overrides, ids));
    }
    final rule = component.prefabRules[prefabId];
    if (rule?['overrides'] != null) {
      final overrides = _rekeyed(overridesFromJson(rule!['overrides']), ids);
      fixed = fixed.withOption('prefabRules', {
        ...component.prefabRules,
        prefabId: {...rule}
          ..remove('overrides')
          ..addAll({if (overrides.isNotEmpty) 'overrides': overrides}),
      });
    }
    return fixed;
  }

  return (
    layout: _throughout(layout, fix),
    prefabs: [
      for (final prefab in prefabs)
        prefab.copyWith(
          root: _everywhere(prefab.root, fix),
          variants: prefab.id != prefabId
              ? null
              : {
                  for (final MapEntry(:key, :value) in prefab.variants.entries)
                    key: PrefabVariant(
                      value.label,
                      _rekeyed(value.overrides, ids),
                    ),
                },
        ),
    ],
  );
}

/// [prefab] with child [from] called [to], and everything that names it.
({Layout layout, List<Prefab> prefabs}) withPartRenamed(
  Layout layout,
  List<Prefab> prefabs,
  Prefab prefab,
  String from,
  String to,
) => withPartIds(
  layout,
  [
    for (final one in prefabs)
      if (one.id != prefab.id) one,
    prefab.copyWith(
      root: _everywhere(
        prefab.root,
        (component) =>
            component.id == from ? component.copyWith(id: to) : component,
      ),
    ),
  ],
  prefab.id,
  {from: to},
);

/// How many instances of [prefabId] there are: in the layout and inside
/// [prefabs].
int instancesOf(String prefabId, Layout layout, Iterable<Prefab> prefabs) => [
  ...layout.all,
  for (final prefab in prefabs) ...prefab.root.all,
].where((component) => component.prefab == prefabId).length;

/// Whether prefab [id] is [of], or holds an instance of it at any depth.
bool holdsPrefab(String id, String of, Map<String, Prefab> prefabs) {
  final seen = <String>{};
  bool holds(String id) =>
      id == of ||
      seen.add(id) &&
          (prefabs[id]?.root.all.any(
                (component) => component.isInstance && holds(component.prefab!),
              ) ??
              false);
  return holds(id);
}

/// [instance] as plain components: its prefab's tree with the instance's
/// variant, overrides and variable values. Children get ids not in [used],
/// which they are added to.
Component unpacked(
  Component instance,
  Map<String, Prefab> prefabs,
  Set<String> used,
) {
  final whole = resolved(instance, prefabs);
  Component named(Component child) {
    final id = freeId(child.id.replaceAll('/', '-'), used);
    used.add(id);
    return child.copyWith(
      id: id,
      children: [for (final inner in child.children) named(inner)],
    );
  }

  return whole.copyWith(
    children: [for (final child in whole.children) named(child)],
  );
}

/// Whether [component] has a plain variable with no value.
bool hasBlank(Component component) => component.vars.values.any(
  (variable) =>
      !variable.isConditional &&
      (variable.value == null || variable.value == ''),
);

/// [pane] with its instances of [prefabId] unpacked, as the pane's rules
/// show them, and its rule for the prefab dropped.
Component _unpackedIn(
  Component component,
  String prefabId,
  Map<String, Prefab> prefabs,
  Set<String> used,
  void Function(Component plain) each,
) {
  if (!component.isPane) return component;
  final shown = component.shown;
  final rules = {...component.prefabRules}..remove(prefabId);
  return component
      .withOption('prefabRules', rules.isEmpty ? null : rules)
      .copyWith(
        children: [
          for (final (index, child) in component.children.indexed)
            if (child.prefab == prefabId)
              () {
                final plain = unpacked(shown[index], prefabs, used);
                each(plain);
                return plain;
              }()
            else
              _unpackedIn(child, prefabId, prefabs, used, each),
        ],
      );
}

/// [layout] with instance [id] unpacked.
Layout withUnpacked(Layout layout, String id, Map<String, Prefab> prefabs) {
  final used = layout.itemIds;
  return layout.rebuild(
    (pane, items) => [
      for (final (index, item) in items.indexed)
        item.id == id && item.isInstance
            // As the pane's rules show it.
            ? unpacked(
                pane.copyWith(children: items).shown[index],
                prefabs,
                used,
              )
            : item,
    ],
  );
}

/// [layout] and the user's prefabs [own] without prefab [prefabId]: each
/// instance is unpacked where it stands. [blank] counts those left with a
/// variable that has no value.
({Layout layout, List<Prefab> prefabs, int instances, int blank}) withoutPrefab(
  Layout layout,
  List<Prefab> own,
  Map<String, Prefab> prefabs,
  String prefabId,
) {
  var instances = 0, blank = 0;
  void each(Component plain) {
    instances++;
    if (hasBlank(plain)) blank++;
  }

  final used = layout.itemIds;
  return (
    layout: layout.copyWith(
      layers: [
        for (final layer in layout.layers)
          layer.withRoot(
            _unpackedIn(layer.root, prefabId, prefabs, used, each),
          ),
      ],
    ),
    prefabs: [
      for (final prefab in own)
        if (prefab.id != prefabId)
          () {
            final ids = {for (final part in prefab.root.all) part.id};
            // A root that is an instance of it is unpacked too.
            final root = prefab.root.prefab == prefabId
                ? unpacked(prefab.root, prefabs, ids)
                : prefab.root;
            if (prefab.root.prefab == prefabId) each(root);
            return prefab.copyWith(
              root: _unpackedIn(root, prefabId, prefabs, ids, each),
            );
          }(),
    ],
    instances: instances,
    blank: blank,
  );
}

/// A prefab made of [item], and the instance that takes its place.
({Prefab prefab, Component instance}) asPrefab(
  Component item,
  String id,
  String name,
) {
  const root = 'root';
  final taken = {for (final part in item.all.skip(1)) part.id};
  return (
    prefab: Prefab(
      id: id,
      name: name,
      root: item.sized(item.w, item.h).copyWith(id: freeId(root, taken)),
    ),
    instance: Component(
      id: item.id,
      prefab: id,
      w: item.w,
      h: item.h,
      x: item.x,
      y: item.y,
      flex: item.flex,
      aspect: item.aspect,
      keep: item.keep,
      hidden: item.hidden,
    ),
  );
}

/// [prefabs] with [changed] in the place of the one with its id, or added.
List<Prefab> withPrefab(List<Prefab> prefabs, Prefab changed) => [
  for (final prefab in prefabs) prefab.id == changed.id ? changed : prefab,
  if (!prefabs.any((prefab) => prefab.id == changed.id)) changed,
];
