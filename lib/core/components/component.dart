import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/style/box_style.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// The kind of a component that is made of others: it arranges its
/// [Component.children] as its [Component.mode] says.
const paneKind = 'pane';

/// What is set differently about the components of a prefab, by the id
/// each has in it: under `options`, `style` and `transform` the values
/// that differ, each by its name, and `hidden`. A value of null hands
/// that one back to whatever is underneath.
typedef Overrides = Map<String, Map<String, Object?>>;

Overrides overridesFromJson(Object? json) => {
  if (json case final Map<Object?, Object?> all)
    for (final MapEntry(:key, :value) in all.entries)
      if (key is String && value is Map<Object?, Object?>) key: value.cast(),
};

double? _positive(double? value) => value != null && value > 0 ? value : null;

Map<String, Object?> _map(Object? json) => switch (json) {
  final Map<Object?, Object?> map => map.cast(),
  _ => const {},
};

/// [overrides] with [values] set for the component [id], each under
/// [section] (`options`, `style`, `transform`), or with no section for
/// `hidden`. A value of null is taken away, and so handed back.
Overrides withOverride(
  Overrides overrides,
  String id,
  Map<String, Object?> values, [
  String? section,
]) {
  final was = overrides[id] ?? const <String, Object?>{};
  final next = section == null
      ? ({...was, ...values}..removeWhere((_, value) => value == null))
      : {
          ...was,
          section: {..._map(was[section]), ...values}
            ..removeWhere((_, value) => value == null),
        };
  next.removeWhere((_, value) => value is Map && value.isEmpty);
  return {
    for (final MapEntry(:key, :value) in overrides.entries)
      if (key != id) key: value,
    if (next.isNotEmpty) id: next,
  };
}

/// [under] with [over] set on top of it, value by value.
Overrides overridesOver(Overrides under, Overrides over) {
  var result = under;
  for (final MapEntry(key: id, value: set) in over.entries) {
    for (final MapEntry(:key, :value) in set.entries) {
      result = value is Map
          ? withOverride(result, id, value.cast(), key)
          : withOverride(result, id, {key: value});
    }
  }
  return result;
}

/// The one thing everything on the screen is: a primitive (text, a
/// picture, a button), something made of other components (a pane), or an
/// instance of a prefab, which is a component that was saved to be used
/// again. Each has options (what its kind lets be set), variables, a
/// transform (its size and place in what holds it), a look and triggers.
@immutable
class Component {
  const Component({
    required this.id,
    this.kind = '',
    this.prefab,
    this.variant,
    this.options = const {},
    this.vars = const {},
    this.style = const {},
    this.on = const {},
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.flex,
    this.aspect,
    this.keep = false,
    this.hidden = false,
    this.children = const [],
    this.overrides = const {},
  });

  /// One made of others. [rules] are its measures (`spacing`, `rowHeight`,
  /// `itemW`, `itemH`, `gap`, `fit`, `align`), which are options like its
  /// title, mode and columns.
  Component.pane({
    required this.id,
    String title = '',
    PaneMode mode = PaneMode.flow,
    int columns = defaultColumns,
    this.children = const [],
    this.style = const {},
    Map<String, Object?> rules = const {},
    Map<String, Map<String, Object?>> prefabRules = const {},
    this.vars = const {},
    this.on = const {},
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.flex,
    this.aspect,
  }) : kind = paneKind,
       prefab = null,
       variant = null,
       keep = false,
       hidden = false,
       overrides = const {},
       options = {
         if (title.isNotEmpty) 'title': title,
         'mode': mode.name,
         'columns': columns,
         ...rules,
         if (prefabRules.isNotEmpty) 'prefabRules': prefabRules,
       };

  /// An instance of the prefab [prefab], which is the one a card is unless
  /// another is named, handed the entity [entityId] as its `source`.
  Component.of(
    String entityId, {
    required this.id,
    String this.prefab = cardPrefabId,
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.variant,
    this.overrides = const {},
    this.style = const {},
    this.on = const {},
  }) : kind = '',
       options = const {},
       vars = {sourceVar: Variable(entityId)},
       flex = null,
       aspect = null,
       keep = false,
       hidden = false,
       children = const [];

  static const defaultColumns = 5;

  /// How round a pane's corners are when its look does not say, in the
  /// TV's pixels.
  static const defaultCorner = 14.0;

  /// The lowest and the tallest a row can be made, in the TV's pixels.
  static const minRowHeight = 16.0, maxRowHeight = 400.0;

  /// The row height a sidebar starts with: a line of small pictures.
  static const barRowHeight = 36.0;

  /// The room a pane keeps between its edge and what is in it when its
  /// look does not say; a global pane keeps none.
  static const defaultPadding = 16.0;

  /// The gap between cells, across and down, when [spacing] is not set.
  static const defaultSpacingX = 20.0, defaultSpacingY = 16.0;
  static const maxSpacing = 80.0;

  /// The columns a new global pane has: enough to place things finely.
  static const globalColumns = 12;
  static const maxColumns = 24;

  /// The tallest a component can be, in cells.
  static const maxRows = 60;

  /// The smallest a component of a [PaneMode.free] pane can be, in cells.
  static const minFreeSpan = 0.25;

  /// How deep panes may be nested, counting the global one.
  static const maxDepth = 4;

  /// The variable the launcher's own prefabs are handed an entity as.
  static const sourceVar = 'source';

  /// Unique within the layout; within its prefab, for one that is part of
  /// a prefab.
  final String id;

  /// What it is: the name of a primitive (`ComponentKind`) or [paneKind].
  /// Nothing for an instance, which is whatever its prefab is.
  final String kind;

  /// The id of the prefab this is an instance of, if it is one. It then
  /// says only what it sets differently; the rest it reads from the prefab
  /// each time it is drawn.
  final String? prefab;

  /// Which of its prefab's variants an instance is; none for the first.
  final String? variant;

  /// What its kind lets be set, by name: a primitive's settings
  /// (`ComponentKind.options`), a pane's title, mode, columns and
  /// measures. An instance's are set over its prefab's.
  final Map<String, Object?> options;

  /// The variables it has of its own, which what is inside it can read
  /// and, where they are public, anything can by its id. Those of an
  /// instance are set over its prefab's.
  final Variables vars;

  /// Its look. An instance's counts over its prefab's.
  final Style style;

  /// What it does, by what sets it off. An instance's counts over its
  /// prefab's, trigger by trigger.
  final Triggers on;

  /// Its transform in a pane of cells: its size, and column and row from
  /// zero. Whole numbers except in [PaneMode.free] panes; [x] and [y] are
  /// not used by [PaneMode.flow] panes.
  final double w, h;
  final double? x, y;

  /// Its transform in a pane that puts things in a line: the share of the
  /// room left over it takes ([flex]), or the shape it keeps ([aspect],
  /// width over height). With neither it takes only what it needs.
  final double? flex, aspect;

  /// True to keep its room in a line while [hidden], so that hiding it
  /// does not change the size of the rest.
  final bool keep;

  /// True for one that is not shown.
  final bool hidden;

  /// What it is made of, for a pane.
  final List<Component> children;

  /// What an instance sets differently about the components of its prefab.
  final Overrides overrides;

  bool get isPane => kind == paneKind;
  bool get isInstance => prefab != null;

  /// The id of the entity it was handed as its variable `source`, which
  /// is what the launcher's own prefabs read as `{{source...}}`.
  String? get source => switch (vars[sourceVar]?.value) {
    final String id when id.isNotEmpty => id,
    _ => null,
  };

  // What a pane's options say, each as what it is.

  String get title => switch (options['title']) {
    final String title => title,
    _ => '',
  };

  PaneMode get mode =>
      PaneMode.values.asNameMap()[options['mode']] ?? PaneMode.flow;

  /// How many cells wide the pane is; more columns mean smaller cells.
  int get columns => switch (options['columns']) {
    final num columns => columns.toInt(),
    _ => defaultColumns,
  };

  double? _measure(String key) => switch (options[key]) {
    final num measure => measure.toDouble(),
    _ => null,
  };

  /// The gap between cells, in the TV's 960-wide pixels, the same across
  /// and down; null for the usual one.
  double? get spacing => _measure('spacing');
  double get spacingX => spacing ?? defaultSpacingX;
  double get spacingY => spacing ?? defaultSpacingY;

  /// How tall a row of cells is, in the TV's 960-wide pixels; null for a
  /// height that follows from how wide a cell is.
  double? get rowHeight => _measure('rowHeight');

  /// The size the pane gives every instance directly in it, whatever each
  /// says for itself. Null leaves that to each of them.
  double? get itemW => _measure('itemW');
  double? get itemH => _measure('itemH');

  /// The room between the things of a pane that puts them in a line.
  double get gap => _measure('gap') ?? 0;

  /// True for a line whose things each take the room they need and are
  /// then made, together, as big as the box allows: a clock, whatever its
  /// box.
  bool get fit => options['fit'] == true;

  /// Where the things of a line sit across the way it runs: `start`,
  /// `center`, `end` or `stretch`. Unsaid, in the middle of a row and
  /// filling the width of a column.
  String? get align => switch (options['align']) {
    final String align => align,
    _ => null,
  };

  /// What the pane says of the instances of a prefab directly in it, by
  /// the prefab's id: which `variant` they are, and what it `overrides`
  /// in them. What an instance says for itself is kept, and counts again
  /// once the rule is gone.
  Map<String, Map<String, Object?>> get prefabRules =>
      overridesFromJson(options['prefabRules']);

  /// [style] as a box is painted from it.
  BoxStyle get box => BoxStyle.of(style);

  /// The properties of a look that mean something to it: a box's, and with
  /// them a primitive's own or, for what holds other things, those the
  /// text inside takes after.
  List<String> get styleKeys => [
    ...boxStyle,
    ...ComponentKind.named(kind)?.style ?? textStyle,
  ];

  /// Whether the pane decides something for what is in it.
  bool get decides => itemW != null || itemH != null || prefabRules.isNotEmpty;

  /// The children as they are to be placed and drawn: instances as the
  /// pane would have them.
  List<Component> get shown {
    if (!decides) return children;
    final rules = prefabRules;
    return [
      for (final child in children)
        if (child.isInstance)
          child.underRule(rules[child.prefab]).copyWith(w: itemW, h: itemH)
        else
          child,
    ];
  }

  /// This instance as [rule], which a pane sets for every instance of a
  /// prefab in it, would have it: its variant and whatever it overrides
  /// count over what the instance says for itself.
  Component underRule(Map<String, Object?>? rule) => rule == null
      ? this
      : copyWith(
          variant: switch (rule['variant']) {
            final String variant => variant,
            _ => variant,
          },
          overrides: overridesOver(
            overrides,
            overridesFromJson(rule['overrides']),
          ),
        );

  /// This component with what [set] says laid over it: see [Overrides].
  Component overridden(Map<String, Object?>? set) {
    if (set == null || set.isEmpty) return this;
    final transform = _map(set['transform']);
    double? number(String key, double? was) => !transform.containsKey(key)
        ? was
        : switch (transform[key]) {
            final num value => value.toDouble(),
            _ => null,
          };
    return Component(
      id: id,
      kind: kind,
      prefab: prefab,
      variant: variant,
      options: {...options, ..._map(set['options'])}
        ..removeWhere((_, value) => value == null),
      vars: vars,
      style: withStyle(style, _map(set['style'])),
      on: on,
      w: number('w', w) ?? 1,
      h: number('h', h) ?? 1,
      x: number('x', x),
      y: number('y', y),
      // None is said as nothing or as 0, which a variant can set over a
      // share its prefab gives.
      flex: _positive(number('flex', flex)),
      aspect: _positive(number('aspect', aspect)),
      keep: switch (transform['keep']) {
        final bool keep => keep,
        _ => keep,
      },
      hidden: switch (set['hidden']) {
        final bool hidden => hidden,
        _ => hidden,
      },
      children: children,
      overrides: overrides,
    );
  }

  /// This component with the option [key] set to [value]; null for the
  /// usual.
  Component withOption(String key, Object? value) => copyWith(
    options: {...options, key: value}..removeWhere((_, value) => value == null),
  );

  /// This pane set up the way a sidebar starts out: a line of small rows,
  /// each a picture with its name beside it, one cell each.
  Component asBar() => copyWith(
    options: {
      ...options,
      'rowHeight': barRowHeight,
      'itemW': 1,
      'itemH': 1,
      'prefabRules': const {
        cardPrefabId: {'variant': 'row'},
        folderPrefabId: {'variant': 'row'},
      },
    },
  );

  /// This pane and every pane inside it.
  Iterable<Component> get panes sync* {
    if (!isPane) return;
    yield this;
    for (final child in children) {
      yield* child.panes;
    }
  }

  /// Everything in this pane and the panes inside it, other than the panes
  /// themselves.
  Iterable<Component> get contents =>
      panes.expand((pane) => pane.children).where((child) => !child.isPane);

  /// This component and everything inside it, at any depth.
  Iterable<Component> get all sync* {
    yield this;
    for (final child in children) {
      yield* child.all;
    }
  }

  /// Whether there is nothing in it but, at most, empty panes.
  bool get isEmpty => children.every((child) => child.isPane && child.isEmpty);

  /// A copy in which the children of every pane, innermost first, have
  /// been replaced by what [change] returns for them.
  Component rebuild(
    List<Component> Function(Component pane, List<Component> children) change,
  ) => !isPane
      ? this
      : copyWith(
          children: change(this, [
            for (final child in children) child.rebuild(change),
          ]),
        );

  /// The id wanted for an instance handed the entity [entityId]: an app's
  /// after its package, which says what it is whatever it is called; any
  /// other after the [name] the device has for it, or failing that the
  /// end of its own id.
  static String autoId(String entityId, [String? name]) =>
      entityId.startsWith('app:')
      ? packageSlug(entityId.substring(4))
      : slugOf(name ?? '', slugOf(entityId.split(RegExp('[:/.]')).last));

  /// This component set up otherwise. A [w] or [h] of null keeps its own.
  Component copyWith({
    String? id,
    String? kind,
    String? prefab,
    String? variant,
    Map<String, Object?>? options,
    Variables? vars,
    Style? style,
    Triggers? on,
    double? w,
    double? h,
    bool? hidden,
    List<Component>? children,
    Overrides? overrides,
  }) => Component(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    prefab: prefab ?? this.prefab,
    variant: variant ?? this.variant,
    options: options ?? this.options,
    vars: vars ?? this.vars,
    style: style ?? this.style,
    on: on ?? this.on,
    w: w ?? this.w,
    h: h ?? this.h,
    x: x,
    y: y,
    flex: flex,
    aspect: aspect,
    keep: keep,
    hidden: hidden ?? this.hidden,
    children: children ?? this.children,
    overrides: overrides ?? this.overrides,
  );

  /// This instance as the first of its prefab's variants, or as [variant].
  Component withVariant(String? variant) => Component(
    id: id,
    kind: kind,
    prefab: prefab,
    variant: variant,
    options: options,
    vars: vars,
    style: style,
    on: on,
    w: w,
    h: h,
    x: x,
    y: y,
    flex: flex,
    aspect: aspect,
    keep: keep,
    hidden: hidden,
    children: children,
    overrides: overrides,
  );

  /// This component at another size and place; with no [x] and [y],
  /// wherever its pane puts it.
  Component sized(double w, double h, {double? x, double? y}) => Component(
    id: id,
    kind: kind,
    prefab: prefab,
    variant: variant,
    options: options,
    vars: vars,
    style: style,
    on: on,
    w: w,
    h: h,
    x: x,
    y: y,
    flex: flex,
    aspect: aspect,
    keep: keep,
    hidden: hidden,
    children: children,
    overrides: overrides,
  );

  /// Throws a [FormatException] for what is not shaped like a component.
  factory Component.fromJson(Map<Object?, Object?> json) {
    final transform =
        jsonOptional<Map<Object?, Object?>>(json, 'transform') ?? const {};
    double? number(String key) => jsonOptional<num>(transform, key)?.toDouble();
    final prefab = jsonOptional<String>(json, 'prefab');
    return Component(
      id: jsonRequired<String>(json, 'id'),
      kind: prefab != null ? '' : jsonRequired<String>(json, 'kind'),
      prefab: prefab,
      variant: jsonOptional<String>(json, 'variant'),
      options: {
        ...?jsonOptional<Map<Object?, Object?>>(json, 'options')?.cast(),
      },
      vars: variablesFromJson(json['vars']),
      style: styleFromJson(json['style']),
      on: triggersFromJson(json['on']),
      w: number('w') ?? 1,
      h: number('h') ?? 1,
      x: number('x'),
      y: number('y'),
      flex: number('flex'),
      aspect: number('aspect'),
      keep: transform['keep'] == true,
      hidden: json['hidden'] == true,
      children: jsonList(json, 'children', Component.fromJson),
      overrides: overridesFromJson(json['overrides']),
    );
  }

  Map<String, Object?> toJson() {
    final transform = {
      if (w != 1) 'w': tidy(w),
      if (h != 1) 'h': tidy(h),
      if (x case final x?) 'x': tidy(x),
      if (y case final y?) 'y': tidy(y),
      if (flex case final flex?) 'flex': tidy(flex),
      'aspect': ?aspect,
      if (keep) 'keep': true,
    };
    return {
      'id': id,
      'prefab': ?prefab,
      if (prefab == null) 'kind': kind,
      'variant': ?variant,
      if (transform.isNotEmpty) 'transform': transform,
      if (hidden) 'hidden': true,
      if (options.isNotEmpty) 'options': options,
      if (vars.isNotEmpty) 'vars': variablesToJson(vars),
      if (style.isNotEmpty) 'style': style,
      if (on.isNotEmpty) 'on': triggersToJson(on),
      if (overrides.isNotEmpty) 'overrides': overrides,
      if (isPane) 'children': [for (final child in children) child.toJson()],
    };
  }
}

/// The prefab an instance handed an entity is of unless it names another,
/// and the one what opens a folder is.
const cardPrefabId = 'app-card';
const folderPrefabId = 'folder-card';
