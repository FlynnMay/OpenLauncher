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
    this.pane,
  });

  /// A pane as an item of the pane around it.
  LayoutItem.pane(Pane this.pane, {this.w = 1, this.h = 1, this.x, this.y})
    : id = 'pane:${pane.id}',
      kind = ItemKind.pane,
      ref = pane.id,
      options = const {},
      style = BoxStyle.none,
      hideName = false;

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
    pane: pane,
  );

  /// This item looking or set up otherwise.
  LayoutItem copyWith({
    BoxStyle? style,
    bool? hideName,
    Map<String, Object?>? options,
  }) => LayoutItem(
    id: id,
    kind: kind,
    ref: ref,
    w: w,
    h: h,
    x: x,
    y: y,
    options: options ?? this.options,
    style: style ?? this.style,
    hideName: hideName ?? this.hideName,
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
  });

  static const defaultColumns = 5;

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
  }) => Pane(
    id: id,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    columns: columns ?? this.columns,
    items: items ?? this.items,
    style: style ?? this.style,
    spacing: identical(spacing, _keep) ? this.spacing : spacing as double?,
    padding: identical(padding, _keep) ? this.padding : padding as double?,
  );

  Pane withItems(List<LayoutItem> items) => Pane(
    id: id,
    title: title,
    mode: mode,
    columns: columns,
    items: items,
    style: style,
    spacing: spacing,
    padding: padding,
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
    if (!style.isEmpty) 'style': style.toJson(),
    'items': [for (final item in items) item.toJson()],
  };
}

/// A surface: the home screen, a rail, or a popup. What is on it is in its
/// global pane, [root].
@immutable
class Panel {
  const Panel({
    required this.id,
    required this.root,
    this.title = '',
    this.position = PopupPosition.center,
    this.size = PopupSize.medium,
  });

  /// A panel with nothing on it yet.
  Panel.empty(
    this.id, {
    this.title = '',
    this.position = PopupPosition.center,
    this.size = PopupSize.medium,
  }) : root = _emptyRoot(id);

  final String id;

  /// Shown as the heading of a popup and as the label of cards opening it.
  final String title;

  /// The pane that fills the panel, edge to edge.
  final Pane root;

  /// Where a popup appears and how much of the screen it takes.
  final PopupPosition position;
  final PopupSize size;

  PanelKind get kind => kindOf(id);

  static PanelKind kindOf(String id) => switch (id) {
    Layout.homeId => PanelKind.home,
    Layout.leftId || Layout.rightId => PanelKind.sidebar,
    _ => PanelKind.popup,
  };

  static String rootId(String panelId) => '$panelId/root';

  static Pane _emptyRoot(String panelId) => switch (kindOf(panelId)) {
    PanelKind.home => Pane(
      id: rootId(panelId),
      mode: PaneMode.grid,
      columns: Pane.globalColumns,
    ),
    PanelKind.sidebar => Pane(id: rootId(panelId), columns: 1),
    PanelKind.popup => Pane(id: rootId(panelId), columns: 4),
  };

  /// Everything on the panel, other than the panes themselves.
  Iterable<LayoutItem> get items => root.contents;

  Panel withRoot(Pane root) =>
      Panel(id: id, title: title, root: root, position: position, size: size);

  factory Panel.fromJson(Map<Object?, Object?> json) {
    final id = _required<String>(json, 'id');
    return Panel(
      id: id,
      title: _optional<String>(json, 'title') ?? '',
      root: switch (_optional<Map<Object?, Object?>>(json, 'pane')) {
        final pane? => Pane.fromJson(pane),
        // Layouts from before panes had a list of sections.
        null => _fromSections(id, _list(json, 'sections', Pane.fromJson)),
      },
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
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (kind == PanelKind.popup) ...{
      'position': position.name,
      'size': size.name,
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
    panels: _list(json, 'panels', Panel.fromJson),
    inbox: _optional<String>(json, 'inbox') ?? '',
    removed: {
      ...?_optional<List<Object?>>(json, 'removed')?.whereType<String>(),
    },
  );

  Map<String, Object?> toJson() => {
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
  /// nested no deeper than [Pane.maxDepth] and not at all in a rail, links
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
        // Too deep, or in a rail: what is in it moves up a level.
        if (kind == PanelKind.sidebar || depth >= Pane.maxDepth) {
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
        pane: repaired,
      );
    }

    repair = (pane, kind, depth) {
      // A rail is a single column of things in order, whatever was asked.
      final rail = kind == PanelKind.sidebar;
      final columns = rail ? 1 : pane.columns.clamp(1, Pane.maxColumns);
      final mode = rail ? PaneMode.flow : pane.mode;
      // The pane's own id first, so that nothing inside can take it.
      final id = fresh(paneIds, pane.id, 'p');
      return Pane(
        id: id,
        title: pane.title,
        mode: mode,
        columns: columns,
        items: [
          for (final entry in pane.items)
            ...fitted(entry, columns, mode, kind, depth),
        ],
        style: pane.style,
        spacing: switch (pane.spacing) {
          final spacing? when spacing.isFinite && !rail =>
            spacing.clamp(0, Pane.maxSpacing).toDouble(),
          _ => null,
        },
        padding: switch (pane.padding) {
          final padding? when padding.isFinite && !rail =>
            padding.clamp(0, Pane.maxPadding).toDouble(),
          _ => null,
        },
      );
    };

    final result = [
      for (final panel in unique)
        panel.withRoot(repair(panel.root, panel.kind, 1)),
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
