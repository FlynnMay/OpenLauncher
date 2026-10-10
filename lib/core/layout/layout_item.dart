import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/box_style.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/pane.dart';

/// One thing placed in a pane.
@immutable
class LayoutItem {
  const LayoutItem({
    required this.id,
    required this.kind,
    required this.ref,
    this.w = 1,
    this.h = 1,
    this.x,
    this.y,
    this.options = const {},
    this.style = BoxStyle.none,
    this.hideName = false,
    this.look = TileLook.card,
    this.pane,
  });

  /// A pane as an item of the pane around it.
  LayoutItem.pane(Pane this.pane, {this.w = 1, this.h = 1, this.x, this.y})
    : id = 'pane:${pane.id}',
      kind = ItemKind.pane,
      ref = pane.id,
      options = const {},
      style = BoxStyle.none,
      hideName = false,
      look = TileLook.card;

  /// Unique within the layout.
  final String id;
  final ItemKind kind;
  final String ref;

  /// Size in the cells of the pane it is in. Whole numbers except in
  /// [PaneMode.free] panes.
  final double w, h;

  /// Column and row, from zero. Not used by [PaneMode.flow] panes.
  final double? x, y;

  /// Settings of a widget, e.g. the place a weather widget shows.
  final Map<String, Object?> options;

  /// How the box behind a card or widget is painted. A pane's own look is
  /// [Pane.style].
  final BoxStyle style;

  /// True to show a card or folder as its picture alone, without its name
  /// under it.
  final bool hideName;

  /// How a card or folder is drawn; the pane it is in may say otherwise
  /// for everything in it ([Pane.itemLook]).
  final TileLook look;

  /// The pane this item is, for [ItemKind.pane].
  final Pane? pane;

  /// The id given to a card that is shown without having been placed.
  static String autoId(String cardId) => 'auto:$cardId';

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
    hideName: hideName,
    look: look,
    pane: pane,
  );

  /// This item looking or set up otherwise.
  LayoutItem copyWith({
    BoxStyle? style,
    bool? hideName,
    TileLook? look,
    Map<String, Object?>? options,
    double? w,
    double? h,
  }) => LayoutItem(
    id: id,
    kind: kind,
    ref: ref,
    w: w ?? this.w,
    h: h ?? this.h,
    x: x,
    y: y,
    options: options ?? this.options,
    style: style ?? this.style,
    hideName: hideName ?? this.hideName,
    look: look ?? this.look,
    pane: pane,
  );

  /// This item at another size and place; with no [x] and [y], wherever
  /// its pane puts it.
  LayoutItem sized(double w, double h, {double? x, double? y}) => LayoutItem(
    id: id,
    kind: kind,
    ref: ref,
    w: w,
    h: h,
    x: x,
    y: y,
    options: options,
    style: style,
    hideName: hideName,
    look: look,
    pane: pane,
  );

  factory LayoutItem.fromJson(Map<Object?, Object?> json) {
    final kind = jsonNamed(
      ItemKind.values,
      jsonOptional<String>(json, 'kind'),
      ItemKind.card,
    );
    final pane = switch (jsonOptional<Map<Object?, Object?>>(json, 'pane')) {
      final pane? when kind == ItemKind.pane => Pane.fromJson(pane),
      _ => null,
    };
    return LayoutItem(
      id: jsonRequired<String>(json, 'id'),
      kind: kind,
      ref: pane?.id ?? jsonRequired<String>(json, 'ref'),
      w: jsonOptional<num>(json, 'w')?.toDouble() ?? 1,
      h: jsonOptional<num>(json, 'h')?.toDouble() ?? 1,
      x: jsonOptional<num>(json, 'x')?.toDouble(),
      y: jsonOptional<num>(json, 'y')?.toDouble(),
      options: {
        ...?jsonOptional<Map<Object?, Object?>>(json, 'options')?.cast(),
      },
      style: BoxStyle.fromJson(json['style']),
      hideName: jsonOptional<bool>(json, 'hideName') ?? false,
      look: jsonNamed(
        TileLook.values,
        jsonOptional<String>(json, 'look'),
        .card,
      ),
      pane: pane,
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
    if (options.isNotEmpty) 'options': options,
    if (!style.isEmpty) 'style': style.toJson(),
    if (hideName) 'hideName': true,
    if (look != TileLook.card) 'look': look.name,
    'pane': ?pane?.toJson(),
  };
}
