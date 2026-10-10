import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/box_style.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';

/// A container with its own cell grid: a background, optionally titled, that
/// holds cards, widgets and other panes. Every panel has one that fills it,
/// the "global" pane; the rest sit inside that, as [ItemKind.pane] items
/// which give them their place and size.
@immutable
class Pane {
  const Pane({
    required this.id,
    this.title = '',
    this.mode = PaneMode.flow,
    this.columns = defaultColumns,
    this.items = const [],
    this.style = BoxStyle.none,
    this.spacing,
    this.padding,
    this.rowHeight,
    this.corners,
    this.itemLook,
    this.itemW,
    this.itemH,
    this.itemNames,
  });

  static const defaultColumns = 5;

  /// How round a pane's corners are when [corners] is not set, and the
  /// roundest one can be made, in the TV's pixels.
  static const defaultCorner = 14.0, maxCorner = 120.0;

  /// The lowest and the tallest a row can be made, in the TV's pixels.
  static const minRowHeight = 16.0, maxRowHeight = 400.0;

  /// The row height a sidebar starts with: a line of small pictures.
  static const barRowHeight = 36.0;

  /// The room a pane keeps between its edge and what is in it when
  /// [padding] is not set; a global pane keeps none.
  static const defaultPadding = 16.0;
  static const maxPadding = 80.0;

  /// The gap between cells, across and down, when [spacing] is not set.
  static const defaultSpacingX = 20.0, defaultSpacingY = 16.0;
  static const maxSpacing = 80.0;

  /// The columns a new global pane has: enough to place things finely.
  static const globalColumns = 12;
  static const maxColumns = 24;

  /// The tallest an item can be, in cells.
  static const maxRows = 60;

  /// The smallest an item of a [PaneMode.free] pane can be, in cells.
  static const minFreeSpan = 0.25;

  /// How deep panes may be nested, counting the global one.
  static const maxDepth = 4;

  final String id;
  final String title;
  final PaneMode mode;

  /// How many cells wide the pane is; more columns mean smaller cells.
  final int columns;
  final List<LayoutItem> items;

  /// How the pane itself is painted. The global pane ignores it: the
  /// wallpaper is its background.
  final BoxStyle style;

  /// The gap between cells, in the TV's 960-wide pixels, the same across and
  /// down; null for the usual one. With the column count it is all that
  /// decides how big a cell is and how far it is from the next.
  final double? spacing;

  /// The room between the pane's edge and what is in it, in the TV's
  /// 960-wide pixels; null for the usual one. It is the same whether or not
  /// the pane has a background or a border.
  final double? padding;

  /// How tall a row of cells is, in the TV's 960-wide pixels; null for a
  /// height that follows from how wide a cell is.
  final double? rowHeight;

  /// How round each corner is, in the TV's 960-wide pixels: top left, top
  /// right, bottom right, bottom left. Null for the usual, all round alike.
  final List<double>? corners;

  /// What the pane makes of every card and folder directly in it, whatever
  /// each says for itself: how it is drawn, how many cells it takes, and
  /// whether its name shows. Null leaves that to each of them. What a card
  /// says for itself is kept, and counts again once the pane stops saying.
  final TileLook? itemLook;
  final double? itemW, itemH;
  final bool? itemNames;

  /// Whether the pane decides something for the cards in it.
  bool get decides =>
      itemLook != null || itemW != null || itemH != null || itemNames != null;

  /// The items as they are to be placed and drawn: cards and folders as the
  /// pane would have them.
  List<LayoutItem> get shown => !decides
      ? items
      : [
          for (final item in items)
            if (item.kind == ItemKind.card || item.kind == ItemKind.panel)
              item.copyWith(
                look: itemLook,
                w: itemW,
                h: itemH,
                hideName: switch (itemNames) {
                  null => null,
                  final names => !names,
                },
              )
            else
              item,
        ];

  double get spacingX => spacing ?? defaultSpacingX;
  double get spacingY => spacing ?? defaultSpacingY;

  static const _keep = Object();

  /// This pane with some of its settings changed. [spacing] and [padding]
  /// may be given as null, for the usual ones.
  Pane copyWith({
    String? title,
    PaneMode? mode,
    int? columns,
    List<LayoutItem>? items,
    BoxStyle? style,
    Object? spacing = _keep,
    Object? padding = _keep,
    Object? rowHeight = _keep,
    Object? corners = _keep,
    Object? itemLook = _keep,
    Object? itemW = _keep,
    Object? itemH = _keep,
    Object? itemNames = _keep,
  }) => Pane(
    id: id,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    columns: columns ?? this.columns,
    items: items ?? this.items,
    style: style ?? this.style,
    spacing: identical(spacing, _keep) ? this.spacing : spacing as double?,
    padding: identical(padding, _keep) ? this.padding : padding as double?,
    rowHeight: identical(rowHeight, _keep)
        ? this.rowHeight
        : rowHeight as double?,
    corners: identical(corners, _keep)
        ? this.corners
        : corners as List<double>?,
    itemLook: identical(itemLook, _keep)
        ? this.itemLook
        : itemLook as TileLook?,
    itemW: identical(itemW, _keep) ? this.itemW : itemW as double?,
    itemH: identical(itemH, _keep) ? this.itemH : itemH as double?,
    itemNames: identical(itemNames, _keep)
        ? this.itemNames
        : itemNames as bool?,
  );

  Pane withItems(List<LayoutItem> items) => copyWith(items: items);

  /// This pane set up the way a sidebar starts out: a line of small rows,
  /// each a picture with its name beside it, one cell each.
  Pane asBar() => copyWith(
    rowHeight: barRowHeight,
    itemLook: TileLook.row,
    itemW: 1.0,
    itemH: 1.0,
  );

  /// This pane and every pane inside it.
  Iterable<Pane> get panes sync* {
    yield this;
    for (final item in items) {
      if (item.pane case final pane?) yield* pane.panes;
    }
  }

  /// Everything in this pane and the panes inside it, other than the panes
  /// themselves.
  Iterable<LayoutItem> get contents =>
      panes.expand((pane) => pane.items).where((item) => item.pane == null);

  /// A copy in which the items of every pane, innermost first, have been
  /// replaced by what [change] returns for them.
  Pane rebuild(
    List<LayoutItem> Function(Pane pane, List<LayoutItem> items) change,
  ) => withItems(
    change(this, [
      for (final item in items)
        switch (item.pane) {
          null => item,
          final pane => item.withPane(pane.rebuild(change)),
        },
    ]),
  );

  factory Pane.fromJson(Map<Object?, Object?> json) => Pane(
    id: jsonRequired<String>(json, 'id'),
    title: jsonOptional<String>(json, 'title') ?? '',
    mode: jsonNamed(PaneMode.values, jsonOptional<String>(json, 'mode'), .flow),
    columns: jsonOptional<num>(json, 'columns')?.toInt() ?? defaultColumns,
    items: jsonList(json, 'items', LayoutItem.fromJson),
    style: BoxStyle.fromJson(json['style']),
    spacing: jsonOptional<num>(json, 'spacing')?.toDouble(),
    padding: jsonOptional<num>(json, 'padding')?.toDouble(),
    rowHeight: jsonOptional<num>(json, 'rowHeight')?.toDouble(),
    corners: switch (jsonOptional<List<Object?>>(json, 'corners')) {
      final List<Object?> corners
          when corners.length == 4 && corners.every((c) => c is num) =>
        [for (final corner in corners) (corner as num).toDouble()],
      _ => null,
    },
    itemLook: TileLook.values
        .asNameMap()[jsonOptional<String>(json, 'itemLook')],
    itemW: jsonOptional<num>(json, 'itemW')?.toDouble(),
    itemH: jsonOptional<num>(json, 'itemH')?.toDouble(),
    itemNames: jsonOptional<bool>(json, 'itemNames'),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'mode': mode.name,
    'columns': columns,
    'spacing': ?switch (spacing) {
      null => null,
      final spacing => tidy(spacing),
    },
    'padding': ?switch (padding) {
      null => null,
      final padding => tidy(padding),
    },
    'rowHeight': ?switch (rowHeight) {
      null => null,
      final rowHeight => tidy(rowHeight),
    },
    'corners': ?corners?.map(tidy).toList(),
    'itemLook': ?itemLook?.name,
    'itemW': ?switch (itemW) {
      null => null,
      final itemW => tidy(itemW),
    },
    'itemH': ?switch (itemH) {
      null => null,
      final itemH => tidy(itemH),
    },
    'itemNames': ?itemNames,
    if (!style.isEmpty) 'style': style.toJson(),
    'items': [for (final item in items) item.toJson()],
  };
}
