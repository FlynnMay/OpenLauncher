import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// One thing placed in a pane.
@immutable
class LayoutItem {
  const LayoutItem({
    required this.id,
    required this.kind,
    required this.ref,
    this.vars = const {},
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.options = const {},
    this.style = const {},
    this.on = const {},
    this.pane,
  });

  /// A pane as an item of the pane around it.
  LayoutItem.pane(Pane this.pane, {this.w = 1, this.h = 1, this.x, this.y})
    : id = paneItemId(pane.id),
      kind = ItemKind.pane,
      ref = pane.id,
      options = const {},
      style = const {},
      on = const {},
      vars = const {};

  /// Unique within the layout.
  final String id;
  final ItemKind kind;
  final String ref;

  /// The variables it has of its own, which what is inside it can read
  /// and, where they are public, anything can by its id. Those of an
  /// instance are set over its prefab's.
  final Variables vars;

  /// The id of the entity an instance of a prefab is drawn from, where
  /// its prefab goes by one: its variable `source`, which is what the
  /// launcher's own prefabs read as `{{source...}}` and do things to.
  String? get source => switch (vars[sourceVar]?.value) {
    final String id when id.isNotEmpty => id,
    _ => null,
  };

  /// The variable an entity is handed to a prefab as.
  static const sourceVar = 'source';

  /// Size in the cells of the pane it is in. Whole numbers except in
  /// [PaneMode.free] panes.
  final double w, h;

  /// Column and row, from zero. Not used by [PaneMode.flow] panes.
  final double? x, y;

  /// Settings of a component, e.g. the place a weather component shows; of a
  /// entity, what it sets differently from the prefab it is an instance of.
  final Map<String, Object?> options;

  /// Its look: how the box behind it is painted, and whatever else what it
  /// is takes ([styleKeys]). An instance's counts over its prefab's. A
  /// pane's own look is [Pane.style].
  final Style style;

  /// The properties of a look that mean something to it: a box's, and with
  /// them a component's own or, for what holds other things, those the text
  /// inside takes after.
  List<String> get styleKeys => [
    ...boxStyle,
    ...switch (kind) {
      ItemKind.component => ComponentKind.named(ref)?.style ?? const [],
      _ => textStyle,
    },
  ];

  /// What it does, by what sets it off, where that is not the usual for
  /// its prefab.
  final Triggers on;

  /// The pane this item is, for [ItemKind.pane].
  final Pane? pane;

  /// The id wanted for the item that holds the pane [paneId]: one that says
  /// it is a pane, once.
  static String paneItemId(String paneId) =>
      paneId.startsWith('pane') ? paneId : 'pane-$paneId';

  /// An instance of the prefab [prefab], which is the one a card is unless
  /// another is named, drawn from the entity [entityId].
  LayoutItem.of(
    String entityId, {
    required this.id,
    String prefab = cardPrefabId,
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.options = const {},
    this.style = const {},
    this.on = const {},
  }) : kind = ItemKind.prefab,
       ref = prefab,
       vars = {sourceVar: Variable(entityId)},
       pane = null;

  /// The id wanted for the entity [entityId]: an app's after its package,
  /// which says what it is whatever it is called; any other after the
  /// [name] the device has for it, or failing that the end of its own id.
  static String autoId(String entityId, [String? name]) =>
      entityId.startsWith('app:')
      ? packageSlug(entityId.substring(4))
      : slugOf(name ?? '', slugOf(entityId.split(RegExp('[:/.]')).last));

  LayoutItem withPane(Pane pane) => LayoutItem(
    id: id,
    kind: kind,
    ref: pane.id,
    vars: vars,
    w: w,
    h: h,
    x: x,
    y: y,
    options: options,
    style: style,
    on: on,
    pane: pane,
  );

  /// This item looking or set up otherwise.
  LayoutItem copyWith({
    String? id,
    String? ref,
    Style? style,
    Triggers? on,
    Variables? vars,
    Map<String, Object?>? options,
    double? w,
    double? h,
  }) => LayoutItem(
    id: id ?? this.id,
    kind: kind,
    ref: ref ?? this.ref,
    vars: vars ?? this.vars,
    w: w ?? this.w,
    h: h ?? this.h,
    x: x,
    y: y,
    options: options ?? this.options,
    style: style ?? this.style,
    on: on ?? this.on,
    pane: pane,
  );

  /// This item at another size and place; with no [x] and [y], wherever
  /// its pane puts it.
  LayoutItem sized(double w, double h, {double? x, double? y}) => LayoutItem(
    id: id,
    kind: kind,
    ref: ref,
    vars: vars,
    w: w,
    h: h,
    x: x,
    y: y,
    options: options,
    style: style,
    on: on,
    pane: pane,
  );

  factory LayoutItem.fromJson(Map<Object?, Object?> json) {
    final named = jsonOptional<String>(json, 'kind');
    // An item from before there were prefabs said `card`, or no kind at
    // all, and named its entity as `ref`. Saves are brought up to date
    // before they are read, so this is met only by the first of those
    // steps, which reads sections through this to make panes of them.
    if (named == null || named == 'card' || named == 'panel') {
      return LayoutItem._legacy(json, folder: named == 'panel');
    }
    // That step meets `widget` too, which is what a component said.
    final kind = named == 'widget'
        ? ItemKind.component
        : jsonNamed(ItemKind.values, named, ItemKind.prefab);
    final pane = switch (jsonOptional<Map<Object?, Object?>>(json, 'pane')) {
      final pane? when kind == ItemKind.pane => Pane.fromJson(pane),
      _ => null,
    };
    return LayoutItem(
      id: jsonRequired<String>(json, 'id'),
      kind: kind,
      ref: pane?.id ?? jsonRequired<String>(json, 'ref'),
      vars: variablesFromJson(json['vars']),
      w: jsonOptional<num>(json, 'w')?.toDouble() ?? 1,
      h: jsonOptional<num>(json, 'h')?.toDouble() ?? 1,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      options: {
        ...?jsonOptional<Map<Object?, Object?>>(json, 'options')?.cast(),
      },
      style: styleFromJson(json['style']),
      on: triggersFromJson(json['on']),
      pane: pane,
    );
  }

  /// What opened a folder said `panel`, and named the folder as `ref`.
  factory LayoutItem._legacy(
    Map<Object?, Object?> json, {
    bool folder = false,
  }) {
    final options = <String, Object?>{
      ...?jsonOptional<Map<Object?, Object?>>(json, 'options')?.cast(),
    };
    // How it said its name was hidden, and that it was drawn as a row.
    if (jsonOptional<bool>(json, 'hideName') ?? false) {
      options[partsOption] = {
        ...?switch (options[partsOption]) {
          final Map<Object?, Object?> parts => parts.cast<String, Object?>(),
          _ => null,
        },
        'name': {hiddenOption: true},
      };
    }
    if (jsonOptional<String>(json, 'look') == 'row') {
      options[layoutOption] = 'row';
    }
    return LayoutItem(
      id: jsonRequired<String>(json, 'id'),
      kind: ItemKind.prefab,
      ref: switch (options.remove('prefab')) {
        final String prefab => prefab,
        _ => folder ? folderPrefabId : cardPrefabId,
      },
      vars: {sourceVar: Variable(jsonRequired<String>(json, 'ref'))},
      w: jsonOptional<num>(json, 'w')?.toDouble() ?? 1,
      h: jsonOptional<num>(json, 'h')?.toDouble() ?? 1,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      options: options,
      style: styleFromJson(json['style']),
      on: triggersFromJson(json['on']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'ref': ref,
    'w': tidy(w),
    'h': tidy(h),
    'x': ?switch (x) {
      null => null,
      final x => tidy(x),
    },
    'y': ?switch (y) {
      null => null,
      final y => tidy(y),
    },
    if (vars.isNotEmpty) 'vars': variablesToJson(vars),
    if (options.isNotEmpty) 'options': options,
    if (style.isNotEmpty) 'style': style,
    if (on.isNotEmpty) 'on': triggersToJson(on),
    'pane': ?pane?.toJson(),
  };
}
