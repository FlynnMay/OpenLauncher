import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/box_style.dart';
import 'package:openlauncher/core/layout/placement.dart';

/// Where a panel is shown. Decided by the panel's id: [Layout.homeId] is the
/// main screen, [Layout.leftId] and [Layout.rightId] are the rails on the
/// screen edges, and every other panel is a popup opened from a card.
enum PanelKind { home, sidebar, popup }

/// How a pane positions its items on its cell grid.
enum PaneMode {
  /// One after another, wrapping at the last column.
  flow,

  /// Each item at its own column and row; gaps are allowed.
  grid,

  /// Each item anywhere, at any size, measured in cells but not held to
  /// them. Items may overlap; later ones are drawn on top.
  free,
}

enum ItemKind {
  /// An app, input or launcher action; [LayoutItem.ref] is the card id.
  card,

  /// Opens a popup panel (this is what a folder is); [LayoutItem.ref] is the
  /// panel id.
  panel,

  /// A launcher widget; [LayoutItem.ref] is the `WidgetKind` name.
  widget,

  /// A pane inside this one, held in [LayoutItem.pane].
  pane,
}

/// How a card or a folder is drawn: its picture with its name under it, or
/// as a row, its picture with its name beside it.
enum TileLook { card, row }

/// The edge of the screen a sidebar is on.
enum BarEdge { left, right, top, bottom }

/// How a sidebar comes open: growing out from its edge over what is in it,
/// sliding in whole, fading in where it will be, or at once.
enum BarOpening { expand, slide, fade, instant }

/// How what is in a sidebar appears: there all along, fading in as the
/// sidebar opens, fading in once it is open, or sliding in from its edge.
enum BarReveal { always, fade, late, slide }

enum PopupPosition { center, bottom, left, right }

enum PopupSize { small, medium, large }

T? _optional<T>(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('"$key" has the wrong type');
}

T _required<T>(Map<Object?, Object?> json, String key) =>
    _optional<T>(json, key) ?? (throw FormatException('"$key" is missing'));

/// Whole numbers are written without a fraction, as the page writes them.
num _tidy(double value) =>
    value == value.roundToDouble() ? value.toInt() : value;

double _hundredths(double value) => (value * 100).roundToDouble() / 100;

T _named<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

List<T> _list<T>(
  Map<Object?, Object?> json,
  String key,
  T Function(Map<Object?, Object?>) parse,
) => [
  for (final entry in _optional<List<Object?>>(json, key) ?? const [])
    if (entry is Map<Object?, Object?>)
      parse(entry)
    else
      throw FormatException('"$key" must hold objects'),
];

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
    final kind = _named(
      ItemKind.values,
      _optional<String>(json, 'kind'),
      ItemKind.card,
    );
    final pane = switch (_optional<Map<Object?, Object?>>(json, 'pane')) {
      final pane? when kind == ItemKind.pane => Pane.fromJson(pane),
      _ => null,
    };
    return LayoutItem(
      id: _required<String>(json, 'id'),
      kind: kind,
      ref: pane?.id ?? _required<String>(json, 'ref'),
      w: _optional<num>(json, 'w')?.toDouble() ?? 1,
      h: _optional<num>(json, 'h')?.toDouble() ?? 1,
      x: _optional<num>(json, 'x')?.toDouble(),
      y: _optional<num>(json, 'y')?.toDouble(),
      options: {...?_optional<Map<Object?, Object?>>(json, 'options')?.cast()},
      style: BoxStyle.fromJson(json['style']),
      hideName: _optional<bool>(json, 'hideName') ?? false,
      look: _named(TileLook.values, _optional<String>(json, 'look'), .card),
      pane: pane,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'ref': ref,
    'w': _tidy(w),
    'h': _tidy(h),
    'x': ?switch (x) {
      null => null,
      final x => _tidy(x),
    },
    'y': ?switch (y) {
      null => null,
      final y => _tidy(y),
    },
    if (options.isNotEmpty) 'options': options,
    if (!style.isEmpty) 'style': style.toJson(),
    if (hideName) 'hideName': true,
    if (look != TileLook.card) 'look': look.name,
    'pane': ?pane?.toJson(),
  };
}

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
    id: _required<String>(json, 'id'),
    title: _optional<String>(json, 'title') ?? '',
    mode: _named(PaneMode.values, _optional<String>(json, 'mode'), .flow),
    columns: _optional<num>(json, 'columns')?.toInt() ?? defaultColumns,
    items: _list(json, 'items', LayoutItem.fromJson),
    style: BoxStyle.fromJson(json['style']),
    spacing: _optional<num>(json, 'spacing')?.toDouble(),
    padding: _optional<num>(json, 'padding')?.toDouble(),
    rowHeight: _optional<num>(json, 'rowHeight')?.toDouble(),
    corners: switch (_optional<List<Object?>>(json, 'corners')) {
      final List<Object?> corners
          when corners.length == 4 && corners.every((c) => c is num) =>
        [for (final corner in corners) (corner as num).toDouble()],
      _ => null,
    },
    itemLook: TileLook.values.asNameMap()[_optional<String>(json, 'itemLook')],
    itemW: _optional<num>(json, 'itemW')?.toDouble(),
    itemH: _optional<num>(json, 'itemH')?.toDouble(),
    itemNames: _optional<bool>(json, 'itemNames'),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'mode': mode.name,
    'columns': columns,
    'spacing': ?switch (spacing) {
      null => null,
      final spacing => _tidy(spacing),
    },
    'padding': ?switch (padding) {
      null => null,
      final padding => _tidy(padding),
    },
    'rowHeight': ?switch (rowHeight) {
      null => null,
      final rowHeight => _tidy(rowHeight),
    },
    'corners': ?corners?.map(_tidy).toList(),
    'itemLook': ?itemLook?.name,
    'itemW': ?switch (itemW) {
      null => null,
      final itemW => _tidy(itemW),
    },
    'itemH': ?switch (itemH) {
      null => null,
      final itemH => _tidy(itemH),
    },
    'itemNames': ?itemNames,
    if (!style.isEmpty) 'style': style.toJson(),
    'items': [for (final item in items) item.toJson()],
  };
}

/// A surface: the home screen, a sidebar on one of its edges, or a popup.
/// What is on it is in its global pane, [root].
@immutable
class Panel {
  const Panel({
    required this.id,
    required this.root,
    this.title = '',
    this.position = PopupPosition.center,
    this.size = PopupSize.medium,
    this.width,
    this.height,
    this.closed,
    this.opening = BarOpening.expand,
    this.reveal = BarReveal.always,
  });

  /// A panel with nothing on it yet.
  Panel.empty(
    this.id, {
    this.title = '',
    this.position = PopupPosition.center,
    this.size = PopupSize.medium,
    this.width,
    this.height,
    this.closed,
    this.opening = BarOpening.expand,
    this.reveal = BarReveal.always,
  }) : root = _emptyRoot(id);

  /// The width or height of a sidebar that takes all the screen has.
  static const fill = double.infinity;

  /// The most a sidebar's size can be set to, in the TV's pixels.
  static const maxExtent = 960.0;

  final String id;

  /// Shown as the heading of a popup and as the label of cards opening it.
  final String title;

  /// The pane that fills the panel, edge to edge.
  final Pane root;

  /// Where a popup appears and how much of the screen it takes.
  final PopupPosition position;
  final PopupSize size;

  /// How big a sidebar is when open, in the TV's 960-wide pixels: [fill]
  /// for all there is, null for what its edge usually has.
  final double? width, height;

  /// How much of a sidebar shows while the focus is elsewhere, measured
  /// out from its edge; 0 hides it. Null for what its edge usually has.
  final double? closed;

  /// How a sidebar comes open, and how what is in it appears as it does.
  final BarOpening opening;
  final BarReveal reveal;

  /// The edge a sidebar is on; null for a panel that is not one.
  BarEdge? get edge => edgeOf(id);

  static BarEdge? edgeOf(String id) => switch (id) {
    Layout.leftId => BarEdge.left,
    Layout.rightId => BarEdge.right,
    Layout.topId => BarEdge.top,
    Layout.bottomId => BarEdge.bottom,
    _ => null,
  };

  /// Whether the sidebar opens across the screen (from the left or right
  /// edge) rather than down or up it.
  bool get opensAcross => edge == BarEdge.left || edge == BarEdge.right;

  /// The sizes a sidebar on this edge has unless told otherwise: along a
  /// side it is as tall as the screen and a few cards wide, closed to a
  /// strip of their pictures; along the top or bottom it is as wide as the
  /// screen and out of sight until the focus goes there.
  double get openWidth => width ?? (opensAcross ? 260 : fill);
  double get openHeight => height ?? (opensAcross ? fill : 120);
  double get closedSize => closed ?? (opensAcross ? 96 : 0);

  PanelKind get kind => kindOf(id);

  static PanelKind kindOf(String id) => switch (id) {
    Layout.homeId => PanelKind.home,
    _ when edgeOf(id) != null => PanelKind.sidebar,
    _ => PanelKind.popup,
  };

  static String rootId(String panelId) => '$panelId/root';

  static Pane _emptyRoot(String panelId) => switch (kindOf(panelId)) {
    PanelKind.home => Pane(
      id: rootId(panelId),
      mode: PaneMode.grid,
      columns: Pane.globalColumns,
    ),
    // A side bar is one column of rows; one along the top or bottom is a
    // row of cards.
    PanelKind.sidebar => switch (edgeOf(panelId)) {
      BarEdge.top || BarEdge.bottom => Pane(id: rootId(panelId), columns: 8),
      _ => Pane(id: rootId(panelId), columns: 1).asBar(),
    },
    PanelKind.popup => Pane(id: rootId(panelId), columns: 4),
  };

  /// Everything on the panel, other than the panes themselves.
  Iterable<LayoutItem> get items => root.contents;

  Panel withRoot(Pane root) => copyWith(root: root);

  static const _keep = Object();

  /// This panel with some of its settings changed. [width], [height] and
  /// [closed] may be given as null, for the usual ones.
  Panel copyWith({
    Pane? root,
    String? title,
    PopupPosition? position,
    PopupSize? size,
    Object? width = _keep,
    Object? height = _keep,
    Object? closed = _keep,
    BarOpening? opening,
    BarReveal? reveal,
  }) => Panel(
    id: id,
    root: root ?? this.root,
    title: title ?? this.title,
    position: position ?? this.position,
    size: size ?? this.size,
    width: identical(width, _keep) ? this.width : width as double?,
    height: identical(height, _keep) ? this.height : height as double?,
    closed: identical(closed, _keep) ? this.closed : closed as double?,
    opening: opening ?? this.opening,
    reveal: reveal ?? this.reveal,
  );

  /// A sidebar's size as written: a number, or the word for all there is.
  static double? _extent(Map<Object?, Object?> json, String key) =>
      switch (json[key]) {
        'fill' => fill,
        final num size when size.isFinite => size.toDouble(),
        _ => null,
      };

  /// [barsFromBefore] is true for a layout saved when a sidebar was always
  /// a list of small rows: its pane is set up to look that way still.
  factory Panel.fromJson(
    Map<Object?, Object?> json, {
    bool barsFromBefore = false,
  }) {
    final id = _required<String>(json, 'id');
    final root = switch (_optional<Map<Object?, Object?>>(json, 'pane')) {
      final pane? => Pane.fromJson(pane),
      // Layouts from before panes had a list of sections.
      null => _fromSections(id, _list(json, 'sections', Pane.fromJson)),
    };
    return Panel(
      id: id,
      title: _optional<String>(json, 'title') ?? '',
      root: barsFromBefore && kindOf(id) == PanelKind.sidebar
          ? root.asBar()
          : root,
      position: _named(
        PopupPosition.values,
        _optional<String>(json, 'position'),
        PopupPosition.center,
      ),
      size: _named(
        PopupSize.values,
        _optional<String>(json, 'size'),
        PopupSize.medium,
      ),
      width: _extent(json, 'width'),
      height: _extent(json, 'height'),
      closed: _optional<num>(json, 'closed')?.toDouble(),
      opening: _named(
        BarOpening.values,
        _optional<String>(json, 'opening'),
        BarOpening.expand,
      ),
      reveal: _named(
        BarReveal.values,
        _optional<String>(json, 'reveal'),
        BarReveal.always,
      ),
    );
  }

  static Object? _written(double? extent) => switch (extent) {
    null => null,
    fill => 'fill',
    final size => _tidy(size),
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (kind == PanelKind.popup) ...{
      'position': position.name,
      'size': size.name,
    },
    if (kind == PanelKind.sidebar) ...{
      'width': ?_written(width),
      'height': ?_written(height),
      'closed': ?_written(closed),
      if (opening != BarOpening.expand) 'opening': opening.name,
      if (reveal != BarReveal.always) 'reveal': reveal.name,
    },
    'pane': root.toJson(),
  };

  // The measurements sections were drawn with, in the TV's 960-wide pixels.
  static const _screenWidth = 960.0, _screenHeight = 540.0, _bottom = 27.0;
  static const _margin = 48.0, _top = 79.0;
  static const _gapX = 20.0, _gapY = 16.0, _cellRatio = 1.45;
  static const _titleHeight = 30.0, _between = 24.0;

  /// The global pane for what used to be a stack of [sections], each now a
  /// pane where it was and as big as it was.
  static Pane _fromSections(String panelId, List<Pane> sections) {
    final kind = kindOf(panelId);
    if (sections.isEmpty) return _emptyRoot(panelId);
    if (kind == PanelKind.sidebar) {
      return _emptyRoot(panelId)
          .withItems([for (final section in sections) ...section.items]);
    }
    // A popup with one plain section looks the same with its items directly
    // in the global pane.
    if (kind == PanelKind.popup &&
        sections.length == 1 &&
        sections.single.title.isEmpty &&
        sections.single.style.isEmpty) {
      return sections.single;
    }
    // A popup's width depends on its size; the common one is assumed.
    final home = kind == PanelKind.home;
    final width = home ? _screenWidth - 2 * _margin : 0.62 * _screenWidth - 64;
    const columns = Pane.globalColumns;
    final full = home ? _screenWidth : width;
    final strideX = (full - (columns - 1) * _gapX) / columns + _gapX;
    final strideY = (strideX - _gapX) / _cellRatio + _gapY;
    var top = home ? _top : 0.0;
    final items = <LayoutItem>[];
    for (final section in sections) {
      const pad = Pane.defaultPadding;
      final cell =
          (width - 2 * pad - (section.columns - 1) * _gapX) / section.columns;
      final rows = rowCount(
        placeItems(section.items, section.columns, section.mode),
      );
      final content =
          2 * pad +
          (section.title.isEmpty ? 0 : _titleHeight) +
          (rows == 0 ? 0 : rows * (cell / _cellRatio + _gapY) - _gapY);
      // A lone pane on the home screen at least reaches the bottom of it:
      // new apps turn up in it, and it scrolls when they do not fit.
      final height = home && sections.length == 1
          ? max(content, _screenHeight - _top - _bottom)
          : content;
      items.add(
        LayoutItem.pane(
          section,
          x: _hundredths((home ? _margin : 0) / strideX),
          y: _hundredths(top / strideY),
          w: _hundredths((width + _gapX) / strideX),
          h: _hundredths((height + _gapY) / strideY),
        ),
      );
      top += height + _between;
    }
    return Pane(
      id: rootId(panelId),
      mode: PaneMode.free,
      columns: columns,
      items: items,
    );
  }
}

/// Everything about where things are on screen.
@immutable
class Layout {
  const Layout({
    required this.panels,
    required this.inbox,
    this.removed = const {},
  });

  static const homeId = 'home';
  static const leftId = 'left';
  static const rightId = 'right';
  static const topId = 'top';
  static const bottomId = 'bottom';

  /// The ids of the sidebars there can be, one for each edge.
  static const barIds = [leftId, rightId, topId, bottomId];

  /// What a layout written now says it is; one that says less was saved
  /// when sidebars were not yet panes like any other.
  static const _version = 2;
  static const _firstPane = 'main';

  /// The home screen with one pane showing [order] first and then every
  /// other card.
  factory Layout.initial([List<String> order = const []]) => Layout(
    inbox: _firstPane,
    panels: [
      Panel(
        id: homeId,
        root: Panel._fromSections(homeId, [
          Pane(
            id: _firstPane,
            items: [
              for (final id in order)
                LayoutItem(
                  id: LayoutItem.autoId(id),
                  kind: ItemKind.card,
                  ref: id,
                ),
            ],
          ),
        ]),
      ),
    ],
  );

  final List<Panel> panels;

  /// The pane that shows cards not placed anywhere, such as newly installed
  /// apps.
  final String inbox;

  /// Cards the user took off the screen altogether. They are not put back
  /// in the [inbox]; placing one anywhere takes it off this list.
  final Set<String> removed;

  Panel get home => panel(homeId)!;

  Panel? panel(String id) {
    for (final panel in panels) {
      if (panel.id == id) return panel;
    }
    return null;
  }

  /// Throws a [FormatException] if [json] is not shaped like a layout. The
  /// result still needs [normalised].
  factory Layout.fromJson(Map<Object?, Object?> json) => Layout(
    panels: _list(
      json,
      'panels',
      (panel) => Panel.fromJson(
        panel,
        barsFromBefore: (_optional<num>(json, 'v') ?? 1) < _version,
      ),
    ),
    inbox: _optional<String>(json, 'inbox') ?? '',
    removed: {
      ...?_optional<List<Object?>>(json, 'removed')?.whereType<String>(),
    },
  );

  Map<String, Object?> toJson() => {
    'v': _version,
    'inbox': inbox,
    'removed': removed.toList(),
    'panels': [for (final panel in panels) panel.toJson()],
  };

  Layout _rebuild(
    List<LayoutItem> Function(Pane pane, List<LayoutItem> items) change, {
    Set<String>? removed,
  }) => Layout(
    inbox: inbox,
    removed: removed ?? this.removed,
    panels: [
      for (final panel in panels) panel.withRoot(panel.root.rebuild(change)),
    ],
  );

  /// A copy with every card in [cardIds] taken off all panels and noted as
  /// [removed].
  Layout without(Set<String> cardIds) => _rebuild(
    (_, items) => [
      for (final item in items)
        if (item.kind != ItemKind.card || !cardIds.contains(item.ref)) item,
    ],
    removed: {...removed, ...cardIds},
  );

  /// A copy with everything the rest of the app relies on made true: a home
  /// panel, unique ids, sizes and positions that fit their pane, panes
  /// nested no deeper than [Pane.maxDepth], links
  /// only to popups that exist, and a valid [inbox].
  Layout normalised() {
    final panelIds = <String>{};
    final unique = [
      for (final panel in panels)
        if (panel.id.isNotEmpty && panelIds.add(panel.id)) panel,
    ];
    if (!panelIds.contains(homeId)) unique.insert(0, Panel.empty(homeId));
    final popups = {
      for (final panel in unique)
        if (panel.kind == PanelKind.popup) panel.id,
    };

    final paneIds = <String>{};
    final itemIds = <String>{};
    String fresh(Set<String> used, String wanted, String prefix) {
      var id = wanted;
      for (var n = used.length; id.isEmpty || !used.add(id); n++) {
        id = '$prefix$n';
      }
      return id;
    }

    late Pane Function(Pane, PanelKind, int) repair;

    /// The item made to fit a pane [columns] wide; several when it is a pane
    /// that cannot stay one, and none when it points at nothing.
    Iterable<LayoutItem> fitted(
      LayoutItem item,
      int columns,
      PaneMode mode,
      PanelKind kind,
      int depth,
    ) sync* {
      final inner = item.pane;
      if (item.kind == ItemKind.pane) {
        if (inner == null) return;
        // Too deep: what is in it moves up a level.
        if (depth >= Pane.maxDepth) {
          for (final entry in inner.items) {
            yield* fitted(entry, columns, mode, kind, depth);
          }
          return;
        }
      } else if (item.ref.isEmpty ||
          item.kind == ItemKind.panel && !popups.contains(item.ref)) {
        return;
      }
      // Only a free pane keeps fractions of a cell.
      final free = mode == PaneMode.free;
      double fit(double value, num low, num high) =>
          ((free ? value : value.roundToDouble()).clamp(low, high)).toDouble();
      final smallest = free ? Pane.minFreeSpan : 1;
      final w = fit(item.w.isFinite ? item.w : 1, smallest, columns);
      final x = item.x, y = item.y;
      // A position is only kept whole; half of one means nothing.
      final placed = x != null && y != null && x.isFinite && y.isFinite;
      final repaired = inner == null ? null : repair(inner, kind, depth + 1);
      yield LayoutItem(
        id: fresh(itemIds, item.id, 'i'),
        kind: item.kind,
        ref: repaired?.id ?? item.ref,
        w: w,
        h: fit(item.h.isFinite ? item.h : 1, smallest, Pane.maxRows),
        x: placed ? fit(x, 0, columns - w) : null,
        y: placed ? fit(y, 0, 999) : null,
        options: item.options,
        style: item.style,
        hideName: item.hideName,
        look: item.look,
        pane: repaired,
      );
    }

    repair = (pane, kind, depth) {
      final columns = pane.columns.clamp(1, Pane.maxColumns);
      // The pane's own id first, so that nothing inside can take it.
      final id = fresh(paneIds, pane.id, 'p');
      // A measure that means something, kept within what is allowed.
      double? within(double? value, num low, num high) =>
          value != null && value.isFinite
          ? value.clamp(low, high).toDouble()
          : null;
      final free = pane.mode == PaneMode.free;
      double? cells(double? value, num most) =>
          switch (within(value, free ? Pane.minFreeSpan : 1, most)) {
            final span? when !free => span.roundToDouble(),
            final span => span,
          };
      return Pane(
        id: id,
        title: pane.title,
        mode: pane.mode,
        columns: columns,
        items: [
          for (final entry in pane.items)
            ...fitted(entry, columns, pane.mode, kind, depth),
        ],
        style: pane.style,
        spacing: within(pane.spacing, 0, Pane.maxSpacing),
        padding: within(pane.padding, 0, Pane.maxPadding),
        rowHeight: within(pane.rowHeight, Pane.minRowHeight, Pane.maxRowHeight),
        corners: switch (pane.corners) {
          final corners?
              when corners.length == 4 &&
                  corners.every((corner) => corner.isFinite) =>
            [
              for (final corner in corners)
                corner.clamp(0, Pane.maxCorner).toDouble(),
            ],
          _ => null,
        },
        itemLook: pane.itemLook,
        itemW: cells(pane.itemW, columns),
        itemH: cells(pane.itemH, Pane.maxRows),
        itemNames: pane.itemNames,
      );
    };

    double? extent(double? size) => size == null || size == Panel.fill
        ? size
        : size.isFinite
        ? size.clamp(40, Panel.maxExtent).toDouble()
        : null;
    final result = [
      for (final panel in unique)
        panel.copyWith(
          root: repair(panel.root, panel.kind, 1),
          width: extent(panel.width),
          height: extent(panel.height),
          closed: switch (panel.closed) {
            final closed? when closed.isFinite =>
              closed.clamp(0, Panel.maxExtent).toDouble(),
            _ => null,
          },
        ),
    ];
    final home = result.firstWhere((panel) => panel.id == homeId);
    final placed = {
      for (final panel in result)
        for (final item in panel.items)
          if (item.kind == ItemKind.card) item.ref,
    };
    return Layout(
      panels: result,
      removed: removed.difference(placed),
      inbox: home.root.panes.any((pane) => pane.id == inbox)
          ? inbox
          : home.root.id,
    );
  }

  /// A copy holding only cards in [cardIds]: items for cards that no longer
  /// exist are dropped, and cards placed nowhere are added to the end of the
  /// [inbox] pane, in the order given, unless the user [removed] them.
  Layout withCards(Iterable<String> cardIds) {
    final known = cardIds.toSet();
    final kept = _rebuild(
      (_, items) => [
        for (final item in items)
          if (item.kind != ItemKind.card || known.contains(item.ref)) item,
      ],
    );
    final placed = {...removed};
    final itemIds = <String>{};
    for (final panel in kept.panels) {
      for (final pane in panel.root.panes) {
        for (final item in pane.items) {
          itemIds.add(item.id);
          if (item.kind == ItemKind.card) placed.add(item.ref);
        }
      }
    }
    final unplaced = [
      for (final id in cardIds)
        if (placed.add(id))
          LayoutItem(
            // Normally free; only taken if the card was once placed under
            // this id and then swapped for another.
            id: itemIds.add(LayoutItem.autoId(id))
                ? LayoutItem.autoId(id)
                : '${LayoutItem.autoId(id)}:${itemIds.length}',
            kind: ItemKind.card,
            ref: id,
          ),
    ];
    return kept._rebuild(
      (pane, items) => pane.id == inbox ? [...items, ...unplaced] : items,
    );
  }
}
