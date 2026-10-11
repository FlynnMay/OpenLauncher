import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/style/box_style.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// A container with its own cell grid: a background, optionally titled, that
/// holds entities, widgets and other panes. Every panel has one that fills it,
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
    this.style = const {},
    this.spacing,
    this.rowHeight,
    this.itemW,
    this.itemH,
    this.rules = const {},
    this.vars = const {},
    this.on = const {},
  });

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

  /// Its look: how the pane itself is painted, the room it keeps inside
  /// (the same whether or not it has a background or a border), and what
  /// the text in it takes after. The global pane is not painted: the
  /// wallpaper is its background.
  final Style style;

  /// [style] as a box is painted from it.
  BoxStyle get box => BoxStyle.of(style);

  /// The gap between cells, in the TV's 960-wide pixels, the same across and
  /// down; null for the usual one. With the column count it is all that
  /// decides how big a cell is and how far it is from the next.
  final double? spacing;

  /// How tall a row of cells is, in the TV's 960-wide pixels; null for a
  /// height that follows from how wide a cell is.
  final double? rowHeight;

  /// The size the pane gives every entity and folder directly in it,
  /// whatever each says for itself. Null leaves that to each of them.
  final double? itemW, itemH;

  /// What the pane says of the instances of a prefab directly in it, by
  /// the prefab's id: which `layout` they use, and under `parts` whatever
  /// it sets for a part of them (`{name: {hidden: true}}`). What an
  /// instance says for itself is kept, and counts again once the rule is
  /// gone.
  final Map<String, Map<String, Object?>> rules;

  /// The variables it has, which everything inside it can read unless
  /// they are private, and anything can by the pane's id where they are
  /// public.
  final Variables vars;

  /// What it does, by what sets it off, where that is not the usual for
  /// what it is: a sidebar revealed makes a layer and moves to it.
  final Triggers on;

  /// Whether the pane decides something for what is in it.
  bool get decides => itemW != null || itemH != null || rules.isNotEmpty;

  /// The items as they are to be placed and drawn: entities and folders as the
  /// pane would have them.
  List<LayoutItem> get shown => !decides
      ? items
      : [
          for (final item in items)
            if (item.kind == ItemKind.prefab)
              item.copyWith(
                w: itemW,
                h: itemH,
                options: switch (rules[prefabIdOf(item)]) {
                  null => null,
                  final rule => underRule(item.options, rule),
                },
              )
            else
              item,
        ];

  double get spacingX => spacing ?? defaultSpacingX;
  double get spacingY => spacing ?? defaultSpacingY;

  static const _keep = Object();

  /// This pane with some of its settings changed. [spacing] and the like
  /// may be given as null, for the usual ones.
  Pane copyWith({
    String? id,
    String? title,
    PaneMode? mode,
    int? columns,
    List<LayoutItem>? items,
    Style? style,
    Object? spacing = _keep,
    Object? rowHeight = _keep,
    Object? itemW = _keep,
    Object? itemH = _keep,
    Map<String, Map<String, Object?>>? rules,
    Variables? vars,
    Triggers? on,
  }) => Pane(
    id: id ?? this.id,
    title: title ?? this.title,
    mode: mode ?? this.mode,
    columns: columns ?? this.columns,
    items: items ?? this.items,
    style: style ?? this.style,
    spacing: identical(spacing, _keep) ? this.spacing : spacing as double?,
    rowHeight: identical(rowHeight, _keep)
        ? this.rowHeight
        : rowHeight as double?,
    itemW: identical(itemW, _keep) ? this.itemW : itemW as double?,
    itemH: identical(itemH, _keep) ? this.itemH : itemH as double?,
    rules: rules ?? this.rules,
    vars: vars ?? this.vars,
    on: on ?? this.on,
  );

  Pane withItems(List<LayoutItem> items) => copyWith(items: items);

  /// This pane set up the way a sidebar starts out: a line of small rows,
  /// each a picture with its name beside it, one cell each.
  Pane asBar() => copyWith(
    rowHeight: barRowHeight,
    itemW: 1.0,
    itemH: 1.0,
    rules: const {
      cardPrefabId: {layoutOption: 'row'},
      folderPrefabId: {layoutOption: 'row'},
    },
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
    style: styleFromJson(json['style']),
    spacing: jsonOptional<num>(json, 'spacing')?.toDouble(),
    rowHeight: jsonOptional<num>(json, 'rowHeight')?.toDouble(),
    itemW: jsonOptional<num>(json, 'itemW')?.toDouble(),
    itemH: jsonOptional<num>(json, 'itemH')?.toDouble(),
    rules: {
      if (json['rules'] case final Map<Object?, Object?> rules)
        for (final MapEntry(:key, :value) in rules.entries)
          if (key is String && value is Map<Object?, Object?>)
            key: value.cast(),
    },
    vars: variablesFromJson(json['vars']),
    on: triggersFromJson(json['on']),
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
    'rowHeight': ?switch (rowHeight) {
      null => null,
      final rowHeight => tidy(rowHeight),
    },
    'itemW': ?switch (itemW) {
      null => null,
      final itemW => tidy(itemW),
    },
    'itemH': ?switch (itemH) {
      null => null,
      final itemH => tidy(itemH),
    },
    if (rules.isNotEmpty) 'rules': rules,
    if (vars.isNotEmpty) 'vars': variablesToJson(vars),
    if (on.isNotEmpty) 'on': triggersToJson(on),
    if (style.isNotEmpty) 'style': style,
    'items': [for (final item in items) item.toJson()],
  };
}
