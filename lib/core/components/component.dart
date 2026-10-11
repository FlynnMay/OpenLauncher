import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/style/box_style.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// The kind of a component that holds [Component.children].
const paneKind = 'pane';

/// Per-child differences from a prefab, keyed by child id. Each entry may
/// hold `options`, `style`, `transform` (maps) and `hidden`. A null value
/// means "inherit".
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

/// Sets [values] for child [id] under [section], or at the top level (for
/// `hidden`) when [section] is null. Null values are removed.
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

/// Merges [over] onto [under], value by value.
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

/// Everything on screen: a primitive (text, picture, button), a pane holding
/// other components, or an instance of a prefab.
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

  /// A pane. [rules] are extra options such as `spacing`, `rowHeight`, `gap`.
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

  /// An instance of [prefab] whose `source` variable is [entityId].
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
       vars = {sourceVar: Variable(entityId, type: VarType.entity)},
       flex = null,
       aspect = null,
       keep = false,
       hidden = false,
       children = const [];

  static const defaultColumns = 5;

  /// Pane corner radius when the style sets none.
  static const defaultCorner = 14.0;

  static const minRowHeight = 16.0, maxRowHeight = 400.0;

  /// Default row height of a sidebar.
  static const barRowHeight = 36.0;

  /// Pane padding when the style sets none.
  static const defaultPadding = 16.0;

  /// Cell gaps when [spacing] is unset.
  static const defaultSpacingX = 20.0, defaultSpacingY = 16.0;
  static const maxSpacing = 80.0;

  /// Columns of a new root pane.
  static const globalColumns = 12;
  static const maxColumns = 24;

  /// Tallest a component can be, in cells.
  static const maxRows = 60;

  /// Smallest size in a [PaneMode.free] pane, in cells.
  static const minFreeSpan = 0.25;

  /// Maximum pane nesting, counting the root.
  static const maxDepth = 4;

  /// The variable name the built-in prefabs use for their entity. Nothing
  /// else gives this name special meaning.
  static const sourceVar = 'source';

  /// Unique in the layout, or within its prefab.
  final String id;

  /// A `ComponentKind` name or [paneKind]. Empty for an instance.
  final String kind;

  /// The prefab this is an instance of, if any. An instance stores only what
  /// differs from it.
  final String? prefab;

  /// The prefab variant; null for the first.
  final String? variant;

  /// Settings defined by the kind. A pane's title, mode, columns and measures
  /// are options too.
  final Map<String, Object?> options;

  /// Its own variables. Children inherit the non-private ones.
  final Variables vars;

  final Style style;

  final Triggers on;

  /// Size and position in the parent pane's cells. Fractions only in
  /// [PaneMode.free]; [x] and [y] are unused in [PaneMode.flow].
  final double w, h;
  final double? x, y;

  /// In a row or column pane: share of the free space ([flex]) or
  /// width/height ratio ([aspect]). With neither it takes its natural size.
  final double? flex, aspect;

  /// Keep its space in a row or column while [hidden].
  final bool keep;

  final bool hidden;

  final List<Component> children;

  /// An instance's differences from its prefab's children.
  final Overrides overrides;

  bool get isPane => kind == paneKind;
  bool get isInstance => prefab != null;

  /// Ids held by its entity-typed variables.
  Iterable<String> get handed => [
    for (final variable in vars.values)
      if (variable.type == VarType.entity)
        if (variable.value case final String id when id.isNotEmpty) id,
  ];

  // Typed access to a pane's options.

  String get title => switch (options['title']) {
    final String title => title,
    _ => '',
  };

  PaneMode get mode =>
      PaneMode.values.asNameMap()[options['mode']] ?? PaneMode.flow;

  int get columns => switch (options['columns']) {
    final num columns => columns.toInt(),
    _ => defaultColumns,
  };

  double? _measure(String key) => switch (options[key]) {
    final num measure => measure.toDouble(),
    _ => null,
  };

  /// Cell gap in TV pixels, both axes; null for the default.
  double? get spacing => _measure('spacing');
  double get spacingX => spacing ?? defaultSpacingX;
  double get spacingY => spacing ?? defaultSpacingY;

  /// Row height in TV pixels; null derives it from the cell width.
  double? get rowHeight => _measure('rowHeight');

  /// Size forced on every instance directly in the pane; null leaves it to
  /// each.
  double? get itemW => _measure('itemW');
  double? get itemH => _measure('itemH');

  /// Gap between children of a row or column pane.
  double get gap => _measure('gap') ?? 0;

  /// Children take their natural size, then the whole row or column is scaled
  /// to fit its box.
  bool get fit => options['fit'] == true;

  /// Cross-axis alignment in a row or column pane: `start`, `center`, `end`
  /// or `stretch`.
  String? get align => switch (options['align']) {
    final String align => align,
    _ => null,
  };

  /// Per-prefab rules for instances directly in the pane: `{prefabId:
  /// {variant, overrides}}`. A rule wins over the instance's own values
  /// without changing them.
  Map<String, Map<String, Object?>> get prefabRules =>
      overridesFromJson(options['prefabRules']);

  BoxStyle get box => BoxStyle.of(style);

  /// Style properties that apply to this component.
  List<String> get styleKeys => [
    ...boxStyle,
    ...ComponentKind.named(kind)?.style ?? textStyle,
  ];

  /// Whether the pane overrides anything on its children.
  bool get decides => itemW != null || itemH != null || prefabRules.isNotEmpty;

  /// The children with the pane's rules applied; what is drawn.
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

  /// This instance with a pane's [rule] applied over its own variant and
  /// overrides.
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

  /// This component with one [Overrides] entry applied.
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
      // 0 means "no flex", so a variant can unset its prefab's.
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

  /// Sets option [key]; null removes it.
  Component withOption(String key, Object? value) => copyWith(
    options: {...options, key: value}..removeWhere((_, value) => value == null),
  );

  /// Sets a pane up as a new sidebar: small rows, row-layout cards.
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

  /// Every non-pane component in this pane and the panes inside it.
  Iterable<Component> get contents =>
      panes.expand((pane) => pane.children).where((child) => !child.isPane);

  /// This component and all its descendants.
  Iterable<Component> get all sync* {
    yield this;
    for (final child in children) {
      yield* child.all;
    }
  }

  /// True if it holds nothing but empty panes.
  bool get isEmpty => children.every((child) => child.isPane && child.isEmpty);

  /// Rebuilds every pane's children with [change], innermost first.
  Component rebuild(
    List<Component> Function(Component pane, List<Component> children) change,
  ) => !isPane
      ? this
      : copyWith(
          children: change(this, [
            for (final child in children) child.rebuild(change),
          ]),
        );

  /// A readable id for an instance of [entityId]: the package slug for an
  /// app, else from the device [name].
  static String autoId(String entityId, [String? name]) =>
      entityId.startsWith('app:')
      ? packageSlug(entityId.substring(4))
      : slugOf(name ?? '', slugOf(entityId.split(RegExp('[:/.]')).last));

  /// A null [w] or [h] keeps the current one.
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

  /// Sets or clears the variant (copyWith cannot clear).
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

  /// Sets size and position; omitted [x] and [y] are cleared.
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

  /// Throws [FormatException] on malformed JSON.
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

/// The built-in card prefabs.
const cardPrefabId = 'app-card';
const folderPrefabId = 'folder-card';
