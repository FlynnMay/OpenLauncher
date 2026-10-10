import 'package:flutter/foundation.dart';

import 'package:openlauncher/core/layout/box_style.dart';

/// Where a panel is shown. Decided by the panel's id: [Layout.homeId] is the
/// main screen, [Layout.leftId] and [Layout.rightId] are the rails on the
/// screen edges, and every other panel is a popup opened from a card.
enum PanelKind { home, sidebar, popup }

/// How a section positions its items on its cell grid.
enum SectionMode {
  /// One after another, wrapping at the last column.
  flow,

  /// Each item at its own column and row; gaps are allowed.
  grid,

  /// Each item anywhere, at any size, measured in cells but not held to
  /// them. Items may overlap; later ones are drawn on top.
  free,
}

enum ItemKind {
  /// An app or input; [LayoutItem.ref] is the card id.
  card,

  /// Opens a popup panel (this is what a folder is); [LayoutItem.ref] is the
  /// panel id.
  panel,

  /// A launcher widget; [LayoutItem.ref] is the `WidgetKind` name.
  widget,
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

/// One thing placed in a section.
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
  });

  /// Unique within the layout.
  final String id;
  final ItemKind kind;
  final String ref;

  /// Size in cells. Whole numbers except in [SectionMode.free] sections.
  final double w, h;

  /// Column and row, from zero. Not used by [SectionMode.flow] sections.
  final double? x, y;

  /// Settings of a widget, e.g. the place a weather widget shows.
  final Map<String, Object?> options;

  /// How the box behind it is painted.
  final BoxStyle style;

  /// The id given to a card that is shown without having been placed.
  static String autoId(String cardId) => 'auto:$cardId';

  LayoutItem copyWith({
    String? id,
    double? w,
    double? h,
    double? x,
    double? y,
  }) => LayoutItem(
    id: id ?? this.id,
    kind: kind,
    ref: ref,
    w: w ?? this.w,
    h: h ?? this.h,
    x: x ?? this.x,
    y: y ?? this.y,
    options: options,
    style: style,
  );

  factory LayoutItem.fromJson(Map<Object?, Object?> json) => LayoutItem(
    id: _required<String>(json, 'id'),
    kind: _named(
      ItemKind.values,
      _optional<String>(json, 'kind'),
      ItemKind.card,
    ),
    ref: _required<String>(json, 'ref'),
    w: _optional<num>(json, 'w')?.toDouble() ?? 1,
    h: _optional<num>(json, 'h')?.toDouble() ?? 1,
    x: _optional<num>(json, 'x')?.toDouble(),
    y: _optional<num>(json, 'y')?.toDouble(),
    options: {...?_optional<Map<Object?, Object?>>(json, 'options')?.cast()},
    style: BoxStyle.fromJson(json['style']),
  );

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
  };
}

/// A titled block of items sharing one cell grid.
@immutable
class Section {
  const Section({
    required this.id,
    this.title = '',
    this.mode = SectionMode.flow,
    this.columns = defaultColumns,
    this.items = const [],
    this.style = BoxStyle.none,
  });

  static const defaultColumns = 5;
  static const maxColumns = 12;
  static const maxSpan = 4;

  /// The smallest an item of a [SectionMode.free] section can be, in cells.
  static const minFreeSpan = 0.25;

  final String id;
  final String title;
  final SectionMode mode;

  /// How many cells wide the section is; more columns mean smaller cards.
  final int columns;
  final List<LayoutItem> items;

  /// How the box around the section is painted.
  final BoxStyle style;

  Section withItems(List<LayoutItem> items) => Section(
    id: id,
    title: title,
    mode: mode,
    columns: columns,
    items: items,
    style: style,
  );

  factory Section.fromJson(Map<Object?, Object?> json) => Section(
    id: _required<String>(json, 'id'),
    title: _optional<String>(json, 'title') ?? '',
    mode: _named(
      SectionMode.values,
      _optional<String>(json, 'mode'),
      SectionMode.flow,
    ),
    columns: _optional<num>(json, 'columns')?.toInt() ?? defaultColumns,
    items: _list(json, 'items', LayoutItem.fromJson),
    style: BoxStyle.fromJson(json['style']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'mode': mode.name,
    'columns': columns,
    if (!style.isEmpty) 'style': style.toJson(),
    'items': [for (final item in items) item.toJson()],
  };
}

/// A surface holding sections: the home screen, a rail, or a popup.
@immutable
class Panel {
  const Panel({
    required this.id,
    this.title = '',
    this.sections = const [],
    this.position = PopupPosition.center,
    this.size = PopupSize.medium,
  });

  final String id;

  /// Shown as the heading of a popup and as the label of cards opening it.
  final String title;
  final List<Section> sections;

  /// Where a popup appears and how much of the screen it takes.
  final PopupPosition position;
  final PopupSize size;

  PanelKind get kind => switch (id) {
    Layout.homeId => PanelKind.home,
    Layout.leftId || Layout.rightId => PanelKind.sidebar,
    _ => PanelKind.popup,
  };

  Iterable<LayoutItem> get items => sections.expand((s) => s.items);

  Panel withSections(List<Section> sections) => Panel(
    id: id,
    title: title,
    sections: sections,
    position: position,
    size: size,
  );

  factory Panel.fromJson(Map<Object?, Object?> json) => Panel(
    id: _required<String>(json, 'id'),
    title: _optional<String>(json, 'title') ?? '',
    sections: _list(json, 'sections', Section.fromJson),
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

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (kind == PanelKind.popup) ...{
      'position': position.name,
      'size': size.name,
    },
    'sections': [for (final section in sections) section.toJson()],
  };
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
  static const _firstSection = 'main';

  /// The home screen with one section showing [order] first and then every
  /// other card.
  factory Layout.initial([List<String> order = const []]) => Layout(
    inbox: _firstSection,
    panels: [
      Panel(
        id: homeId,
        sections: [
          Section(
            id: _firstSection,
            items: [
              for (final id in order)
                LayoutItem(
                  id: LayoutItem.autoId(id),
                  kind: ItemKind.card,
                  ref: id,
                ),
            ],
          ),
        ],
      ),
    ],
  );

  final List<Panel> panels;

  /// The section that shows cards not placed anywhere, such as newly
  /// installed apps.
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

  /// A copy with every card in [cardIds] taken off all panels and noted as
  /// [removed].
  Layout without(Set<String> cardIds) => Layout(
    inbox: inbox,
    removed: {...removed, ...cardIds},
    panels: [
      for (final panel in panels)
        panel.withSections([
          for (final section in panel.sections)
            section.withItems([
              for (final item in section.items)
                if (item.kind != ItemKind.card || !cardIds.contains(item.ref))
                  item,
            ]),
        ]),
    ],
  );

  /// A copy with everything the rest of the app relies on made true: a home
  /// panel with at least one section, unique ids, sizes and positions within
  /// their section, links only to popups that exist, and a valid [inbox].
  Layout normalised() {
    final panelIds = <String>{};
    final unique = [
      for (final panel in panels)
        if (panel.id.isNotEmpty && panelIds.add(panel.id)) panel,
    ];
    if (!panelIds.contains(homeId)) unique.insert(0, const Panel(id: homeId));
    final popups = {
      for (final panel in unique)
        if (panel.kind == PanelKind.popup) panel.id,
    };

    final sectionIds = <String>{};
    final itemIds = <String>{};
    String fresh(Set<String> used, String wanted, String prefix) {
      var id = wanted;
      for (var n = used.length; id.isEmpty || !used.add(id); n++) {
        id = '$prefix$n';
      }
      return id;
    }

    LayoutItem? item(LayoutItem item, int columns, SectionMode mode) {
      if (item.ref.isEmpty) return null;
      if (item.kind == ItemKind.panel && !popups.contains(item.ref)) {
        return null;
      }
      // Only a free section keeps fractions of a cell.
      final free = mode == SectionMode.free;
      double fit(double value, num low, num high) =>
          ((free ? value : value.roundToDouble()).clamp(low, high)).toDouble();
      final smallest = free ? Section.minFreeSpan : 1;
      final w = fit(item.w.isFinite ? item.w : 1, smallest, columns);
      final x = item.x, y = item.y;
      // A position is only kept whole; half of one means nothing.
      final placed = x != null && y != null && x.isFinite && y.isFinite;
      return LayoutItem(
        id: fresh(itemIds, item.id, 'i'),
        kind: item.kind,
        ref: item.ref,
        w: w,
        h: fit(item.h.isFinite ? item.h : 1, smallest, Section.maxSpan),
        x: placed ? fit(x, 0, columns - w) : null,
        y: placed ? fit(y, 0, 999) : null,
        options: item.options,
        style: item.style,
      );
    }

    Section section(Section section, PanelKind kind) {
      // A rail is a single column whatever was asked for.
      final columns = kind == PanelKind.sidebar
          ? 1
          : section.columns.clamp(1, Section.maxColumns);
      final mode = kind == PanelKind.sidebar ? SectionMode.flow : section.mode;
      return Section(
        id: fresh(sectionIds, section.id, 's'),
        title: section.title,
        mode: mode,
        columns: columns,
        items: [for (final entry in section.items) ?item(entry, columns, mode)],
        style: section.style,
      );
    }

    final result = [
      for (final panel in unique)
        panel.withSections([
          for (final entry in panel.sections) section(entry, panel.kind),
          if (panel.sections.isEmpty && panel.kind != PanelKind.sidebar)
            section(
              Section(id: panel.id == homeId ? _firstSection : ''),
              panel.kind,
            ),
        ]),
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
      inbox: home.sections.any((s) => s.id == inbox)
          ? inbox
          : home.sections.first.id,
    );
  }

  /// A copy holding only cards in [cardIds]: items for cards that no longer
  /// exist are dropped, and cards placed nowhere are added to the end of the
  /// [inbox] section, in the order given, unless the user [removed] them.
  Layout withCards(Iterable<String> cardIds) {
    final known = cardIds.toSet();
    final placed = {...removed};
    final kept = [
      for (final panel in panels)
        panel.withSections([
          for (final section in panel.sections)
            section.withItems([
              for (final item in section.items)
                if (item.kind != ItemKind.card || known.contains(item.ref))
                  item,
            ]),
        ]),
    ];
    for (final panel in kept) {
      for (final item in panel.items) {
        if (item.kind == ItemKind.card) placed.add(item.ref);
      }
    }
    final itemIds = {
      for (final panel in kept)
        for (final item in panel.items) item.id,
    };
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
    return Layout(
      inbox: inbox,
      removed: removed,
      panels: [
        for (final panel in kept)
          panel.withSections([
            for (final section in panel.sections)
              section.id == inbox
                  ? section.withItems([...section.items, ...unplaced])
                  : section,
          ]),
      ],
    );
  }
}
