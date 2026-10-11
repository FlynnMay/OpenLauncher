import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/box_style.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';

/// One thing placed in a pane.
@immutable
class LayoutItem {
  const LayoutItem({
    required this.id,
    required this.kind,
    required this.ref,
    this.source,
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.options = const {},
    this.style = BoxStyle.none,
    this.on = const {},
    this.pane,
  });

  /// A pane as an item of the pane around it.
  LayoutItem.pane(Pane this.pane, {this.w = 1, this.h = 1, this.x, this.y})
    : id = paneItemId(pane.id),
      kind = ItemKind.pane,
      ref = pane.id,
      options = const {},
      style = BoxStyle.none,
      on = const {},
      source = null;

  /// Unique within the layout.
  final String id;
  final ItemKind kind;
  final String ref;

  /// The id of the entity a prefab's instance is drawn from: what its
  /// templates read as `{{source...}}`, and what its actions are done to.
  final String? source;

  /// Size in the cells of the pane it is in. Whole numbers except in
  /// [PaneMode.free] panes.
  final double w, h;

  /// Column and row, from zero. Not used by [PaneMode.flow] panes.
  final double? x, y;

  /// Settings of a widget, e.g. the place a weather widget shows; of a
  /// entity, what it sets differently from the prefab it is an instance of.
  final Map<String, Object?> options;

  /// How the box behind an entity or widget is painted. A pane's own look is
  /// [Pane.style].
  final BoxStyle style;

  /// What it does, by what sets it off, where that is not the usual for
  /// its kind (`usualTriggers`).
  final Triggers on;

  /// The pane this item is, for [ItemKind.pane].
  final Pane? pane;

  /// The id wanted for the item that holds the pane [paneId]: one that says
  /// it is a pane, once.
  static String paneItemId(String paneId) =>
      paneId.startsWith('pane') ? paneId : 'pane-$paneId';

  /// An instance of the prefab [prefab], which is the one a card is unless
  /// another is named, drawn from the entity [entityId].
  const LayoutItem.of(
    String entityId, {
    required this.id,
    String prefab = cardPrefabId,
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.options = const {},
    this.style = BoxStyle.none,
    this.on = const {},
  }) : kind = ItemKind.prefab,
       ref = prefab,
       source = entityId,
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
    BoxStyle? style,
    Triggers? on,
    Map<String, Object?>? options,
    double? w,
    double? h,
  }) => LayoutItem(
    id: id ?? this.id,
    kind: kind,
    ref: ref ?? this.ref,
    source: source,
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
    source: source,
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
    if (named == null || named == 'card') return LayoutItem._legacy(json);
    final kind = jsonNamed(ItemKind.values, named, ItemKind.prefab);
    final pane = switch (jsonOptional<Map<Object?, Object?>>(json, 'pane')) {
      final pane? when kind == ItemKind.pane => Pane.fromJson(pane),
      _ => null,
    };
    return LayoutItem(
      id: jsonRequired<String>(json, 'id'),
      kind: kind,
      ref: pane?.id ?? jsonRequired<String>(json, 'ref'),
      source: jsonOptional<String>(json, 'source'),
      w: jsonOptional<num>(json, 'w')?.toDouble() ?? 1,
      h: jsonOptional<num>(json, 'h')?.toDouble() ?? 1,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      options: {
        ...?jsonOptional<Map<Object?, Object?>>(json, 'options')?.cast(),
      },
      style: BoxStyle.fromJson(json['style']),
      on: triggersFromJson(json['on']),
      pane: pane,
    );
  }

  factory LayoutItem._legacy(Map<Object?, Object?> json) {
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
      ref: switch (options.remove(prefabOption)) {
        final String prefab => prefab,
        _ => cardPrefabId,
      },
      source: jsonRequired<String>(json, 'ref'),
      w: jsonOptional<num>(json, 'w')?.toDouble() ?? 1,
      h: jsonOptional<num>(json, 'h')?.toDouble() ?? 1,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      options: options,
      style: BoxStyle.fromJson(json['style']),
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
    'source': ?source,
    if (options.isNotEmpty) 'options': options,
    if (!style.isEmpty) 'style': style.toJson(),
    if (on.isNotEmpty) 'on': triggersToJson(on),
    'pane': ?pane?.toJson(),
  };
}
