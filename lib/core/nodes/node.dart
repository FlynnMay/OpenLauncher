import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/transform.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

export 'package:openlauncher/core/nodes/transform.dart';

/// Differences from a prefab, node by node, keyed by node id. Each is part of a
/// node: `modules` (each a map of values), `transform`, `hidden`, `name`. A
/// null value means "inherit".
typedef Overrides = Map<String, Map<String, Object?>>;

Overrides overridesFromJson(Object? json) => {
  if (json case final Map<Object?, Object?> all)
    for (final MapEntry(:key, :value) in all.entries)
      if (key is String && value is Map<Object?, Object?>) key: value.cast(),
};

Map<String, Object?> _map(Object? json) => switch (json) {
  final Map<Object?, Object?> map => map.cast(),
  _ => const {},
};

/// Sets [values] on node [id]: in module [module], or at the top level
/// (`hidden`, `name`, `transform`) when [module] is null. Null values are
/// removed, and so is anything left empty.
Overrides withOverride(
  Overrides overrides,
  String id,
  Map<String, Object?> values, [
  String? module,
]) {
  final was = overrides[id] ?? const <String, Object?>{};
  final Map<String, Object?> next;
  if (module == null) {
    next = {...was, ...values}..removeWhere((_, value) => value == null);
  } else {
    final modules = _map(was['modules']);
    final set = {..._map(modules[module]), ...values}
      ..removeWhere((_, value) => value == null);
    next = {
      ...was,
      'modules': {
        for (final MapEntry(:key, :value) in modules.entries)
          if (key != module) key: value,
        if (set.isNotEmpty) module: set,
      },
    };
  }
  next.removeWhere((_, value) => value is Map && value.isEmpty);
  return {
    for (final MapEntry(:key, :value) in overrides.entries)
      if (key != id) key: value,
    if (next.isNotEmpty) id: next,
  };
}

/// Merges [over] onto [under], value by value.
Overrides overridesOver(Overrides under, Overrides over) {
  var result = under;
  for (final MapEntry(key: id, value: set) in over.entries) {
    for (final MapEntry(:key, :value) in set.entries) {
      if (key == 'modules') {
        for (final MapEntry(key: module, value: values) in _map(
          value,
        ).entries) {
          result = withOverride(result, id, _map(values), module);
        }
      } else {
        result = withOverride(result, id, {key: value});
      }
    }
  }
  return result;
}

/// The modules of a node: module name -> its values.
typedef Modules = Map<String, ModuleValues>;

Modules modulesFromJson(Object? json) => {
  if (json case final Map<Object?, Object?> all)
    for (final MapEntry(:key, :value) in all.entries)
      if (key is String && value is Map<Object?, Object?>) key: value.cast(),
};

/// Everything on screen is a node in one tree: what it draws, how it
/// arranges its children and how it behaves come from its modules. An
/// instance of a prefab stores only what differs from it.
@immutable
class Node {
  const Node({
    required this.id,
    this.name = '',
    this.prefab,
    this.variant,
    this.transform = NodeTransform.fill,
    this.modules = const {},
    this.hidden = false,
    this.children = const [],
    this.overrides = const {},
  });

  /// A node that holds others: laid out as [mode] ([PaneMode.free] for no
  /// Layout), with [layout] adding Layout values. Cells scroll down unless
  /// [scroll] says otherwise.
  factory Node.pane({
    required String id,
    String name = '',
    PaneMode mode = PaneMode.flow,
    int columns = LayoutModule.defaultColumns,
    List<Node> children = const [],
    Style style = const {},
    ModuleValues layout = const {},
    ModuleValues? scroll,
    ModuleValues? dock,
    Map<String, Map<String, Object?>> prefabRules = const {},
    Variables vars = const {},
    Triggers on = const {},
    double w = 1,
    double h = 1,
    double? x,
    double? y,
    double? flex,
    double? aspect,
  }) {
    final cells = mode == PaneMode.flow || mode == PaneMode.grid;
    return Node(
      id: id,
      name: name,
      children: children,
      modules: {
        if (mode != PaneMode.free)
          layoutModule.name: {'mode': mode.name, 'columns': columns, ...layout},
        scrollModule.name: ?scroll ?? (cells ? const {'down': true} : null),
        dockModule.name: ?dock,
        if (style.isNotEmpty) styleModule.name: style,
        if (prefabRules.isNotEmpty) prefabRulesModule.name: prefabRules,
        if (vars.isNotEmpty) variablesModule.name: variablesToJson(vars),
        if (on.isNotEmpty) triggersModule.name: triggersToJson(on),
        sizingModule.name: ?_sizing(w, h, x, y, flex, aspect),
      },
    );
  }

  /// An instance of [prefab] handed [entityId] in its [variable].
  factory Node.of(
    String entityId, {
    required String id,
    required String prefab,
    required String variable,
    double w = 1,
    double h = 1,
    double? x,
    double? y,
    String? variant,
    Overrides overrides = const {},
    Style style = const {},
    Triggers on = const {},
  }) => Node(
    id: id,
    prefab: prefab,
    variant: variant,
    overrides: overrides,
    modules: {
      variablesModule.name: variablesToJson({
        variable: Variable(entityId, type: VarType.entity),
      }),
      if (style.isNotEmpty) styleModule.name: style,
      if (on.isNotEmpty) triggersModule.name: triggersToJson(on),
      sizingModule.name: ?_sizing(w, h, x, y, null, null),
    },
  );

  static ModuleValues? _sizing(
    double w,
    double h,
    double? x,
    double? y,
    double? flex,
    double? aspect,
  ) {
    final sizing = {
      if (w != 1) 'w': tidy(w),
      if (h != 1) 'h': tidy(h),
      if (x != null) 'x': tidy(x),
      if (y != null) 'y': tidy(y),
      if (flex != null) 'flex': tidy(flex),
      'aspect': ?aspect,
    };
    return sizing.isEmpty ? null : sizing;
  }

  /// Deepest nesting, counting the root. A docked node counts as one.
  static const maxDepth = 4;

  /// Unique in the layout, or within its prefab.
  final String id;

  /// What the editor calls it.
  final String name;

  /// The prefab this is an instance of, if any.
  final String? prefab;

  /// The prefab variant; null for the first.
  final String? variant;

  /// Where it sits in a parent without a Layout.
  final NodeTransform transform;

  final Modules modules;

  final bool hidden;

  final List<Node> children;

  /// An instance's differences from its prefab's nodes.
  final Overrides overrides;

  bool get isInstance => prefab != null;

  /// The values of [module], if it has it.
  ModuleValues? values(String module) => modules[module];

  bool has(String module) => modules.containsKey(module);

  /// With [module] set to [values]; null removes it.
  Node withModule(String module, ModuleValues? values) => copyWith(
    modules: {
      for (final MapEntry(:key, :value) in modules.entries)
        if (key != module) key: value,
      module: ?values,
    },
  );

  /// With [key] of [module] set, adding the module if it has none; null
  /// removes the key.
  Node withValue(String module, String key, Object? value) => withModule(
    module,
    {...?modules[module], key: value}..removeWhere((_, value) => value == null),
  );

  /// This node with one [Overrides] entry applied.
  Node overridden(Map<String, Object?>? set) {
    if (set == null || set.isEmpty) return this;
    final over = modulesFromJson(set['modules']);
    return Node(
      id: id,
      name: switch (set['name']) {
        final String name => name,
        _ => name,
      },
      prefab: prefab,
      variant: variant,
      transform: set.containsKey('transform')
          ? NodeTransform.fromJson(set['transform'])
          : transform,
      modules: {
        ...modules,
        for (final MapEntry(key: module, :value) in over.entries)
          module: (moduleNamed(module)?.merge ?? mergeValues)(
            modules[module] ?? const {},
            value,
          ),
      },
      hidden: switch (set['hidden']) {
        final bool hidden => hidden,
        _ => hidden,
      },
      children: children,
      overrides: overrides,
    );
  }

  /// This node and all its descendants.
  Iterable<Node> get all sync* {
    yield this;
    for (final child in children) {
      yield* child.all;
    }
  }

  /// A readable id for an instance of [entityId]: from the dotted name its
  /// id ends in (an app's package), else from its [name], else from the end
  /// of its id.
  static String autoId(String entityId, [String? name]) {
    final tail = entityId.split(RegExp('[:/]')).last;
    return tail.contains('.')
        ? packageSlug(tail)
        : slugOf(name ?? '', slugOf(tail));
  }

  Node copyWith({
    String? id,
    String? name,
    String? prefab,
    String? variant,
    NodeTransform? transform,
    Modules? modules,
    bool? hidden,
    List<Node>? children,
    Overrides? overrides,
  }) => Node(
    id: id ?? this.id,
    name: name ?? this.name,
    prefab: prefab ?? this.prefab,
    variant: variant ?? this.variant,
    transform: transform ?? this.transform,
    modules: modules ?? this.modules,
    hidden: hidden ?? this.hidden,
    children: children ?? this.children,
    overrides: overrides ?? this.overrides,
  );

  /// Sets or clears the variant (copyWith cannot clear).
  Node withVariant(String? variant) => Node(
    id: id,
    name: name,
    prefab: prefab,
    variant: variant,
    transform: transform,
    modules: modules,
    hidden: hidden,
    children: children,
    overrides: overrides,
  );

  /// Throws [FormatException] on malformed JSON. An instance's nodes
  /// variables become its children: one node per slot, holding its nodes.
  factory Node.fromJson(Map<Object?, Object?> json) {
    final id = jsonRequired<String>(json, 'id');
    final prefab = jsonOptional<String>(json, 'prefab');
    var modules = modulesFromJson(json['modules']);
    final holders = <Node>[];
    if (prefab != null) {
      final vars = modules[variablesModule.name] ?? const {};
      for (final MapEntry(key: name, :value) in vars.entries) {
        final nodes = switch (value) {
          final List<Object?> list => list,
          {'value': final List<Object?> list} => list,
          _ => null,
        };
        if (nodes == null ||
            !nodes.every((node) => node is Map && node['id'] is String)) {
          continue;
        }
        holders.add(
          Node(
            id: slotHolderId(id, name),
            modules: {
              slotModule.name: {'variable': name},
            },
            children: [
              for (final node in nodes)
                Node.fromJson(node! as Map<Object?, Object?>),
            ],
          ),
        );
      }
      if (holders.isNotEmpty) {
        final rest = {
          for (final MapEntry(:key, :value) in vars.entries)
            if (!holders.any((holder) => holder.slotVariable == key))
              key: value,
        };
        modules = {
          for (final MapEntry(:key, :value) in modules.entries)
            if (key != variablesModule.name) key: value,
          if (rest.isNotEmpty) variablesModule.name: rest,
        };
      }
    }
    return Node(
      id: id,
      name: jsonOptional<String>(json, 'name') ?? '',
      prefab: prefab,
      variant: jsonOptional<String>(json, 'variant'),
      transform: NodeTransform.fromJson(json['transform']),
      modules: modules,
      hidden: json['hidden'] == true,
      children: [...jsonList(json, 'children', Node.fromJson), ...holders],
      overrides: overridesFromJson(json['overrides']),
    );
  }

  Map<String, Object?> toJson() {
    final holders = isInstance
        ? children.where((child) => child.holdsSlot).toList()
        : const <Node>[];
    final saved = holders.isEmpty
        ? modules
        : {
            ...modules,
            variablesModule.name: {
              ...?modules[variablesModule.name],
              for (final holder in holders)
                holder.slotVariable!: [
                  for (final node in holder.children) node.toJson(),
                ],
            },
          };
    final own = [
      for (final child in children)
        if (!holders.contains(child)) child,
    ];
    return {
      'id': id,
      if (name.isNotEmpty) 'name': name,
      'prefab': ?prefab,
      'variant': ?variant,
      if (!transform.isFill) 'transform': transform.toJson(),
      if (hidden) 'hidden': true,
      if (saved.isNotEmpty) 'modules': saved,
      if (overrides.isNotEmpty) 'overrides': overrides,
      if (own.isNotEmpty) 'children': [for (final child in own) child.toJson()],
    };
  }
}
