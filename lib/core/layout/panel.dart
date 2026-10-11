import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/rules.dart';

/// A surface: the home screen, a sidebar on one of its edges, or a popup.
/// What is on it is in its global pane, [root].
@immutable
class Panel {
  const Panel({
    required this.id,
    required this.root,
    this.title = '',
    this.rules = const {},
  });

  /// A panel with nothing on it yet.
  Panel.empty(this.id, {this.title = '', this.rules = const {}})
    : root = _emptyRoot(id);

  /// The width or height of a sidebar that takes all the screen has.
  static const fill = double.infinity;

  /// The most a sidebar's size can be set to, in the TV's pixels.
  static const maxExtent = 960.0;

  final String id;

  /// Shown as the heading of a popup and as the label of entities opening it.
  final String title;

  /// The pane that fills the panel, edge to edge.
  final Pane root;

  /// What it is set to as a pane that is shown and hidden, each under the
  /// name [panelRules] describes it by: where a folder opens and how big,
  /// how a sidebar comes open. With them a sidebar's `width`, `height` and
  /// `closed`, in the TV's 960-wide pixels, the first two `fill` for all
  /// there is. What is not among them is as usual.
  final Map<String, Object?> rules;

  /// What it has for the rule [key]: what it is set to, or the usual.
  Object? rule(String key) =>
      rules[key] ??
      panelRules(kind).where((rule) => rule.key == key).firstOrNull?.usual;

  /// This panel with the rule [key] set to [value]; null for the usual.
  Panel withRule(String key, Object? value) => copyWith(
    rules: {...rules, key: value == fill ? 'fill' : value}
      ..removeWhere((_, value) => value == null),
  );

  double? _extent(String key) => switch (rules[key]) {
    'fill' => fill,
    final num size => size.toDouble(),
    _ => null,
  };

  /// How big a sidebar is when open: [fill] for all there is, null for
  /// what its edge usually has.
  double? get width => _extent('width');
  double? get height => _extent('height');

  /// How much of a sidebar shows while the focus is elsewhere, measured
  /// out from its edge; 0 hides it. Null for what its edge usually has.
  double? get closed => _extent('closed');

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
  /// side it is as tall as the screen and a few entities wide, closed to a
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

  /// The key, in `LauncherConfig.iconOverrides`, of the picture the user
  /// gave what opens the folder [panelId].
  static String iconKey(String panelId) => 'panel:$panelId';

  static Pane _emptyRoot(String panelId) => switch (kindOf(panelId)) {
    PanelKind.home => Pane(
      id: rootId(panelId),
      mode: PaneMode.grid,
      columns: Pane.globalColumns,
    ),
    // A side bar is one column of rows; one along the top or bottom is a
    // row of entities.
    PanelKind.sidebar => switch (edgeOf(panelId)) {
      BarEdge.top || BarEdge.bottom => Pane(id: rootId(panelId), columns: 8),
      _ => Pane(id: rootId(panelId), columns: 1).asBar(),
    },
    PanelKind.popup => Pane(id: rootId(panelId), columns: 4),
  };

  /// Everything on the panel, other than the panes themselves.
  Iterable<LayoutItem> get items => root.contents;

  Panel withRoot(Pane root) => copyWith(root: root);

  Panel copyWith({
    String? id,
    Pane? root,
    String? title,
    Map<String, Object?>? rules,
  }) => Panel(
    id: id ?? this.id,
    root: root ?? this.root,
    title: title ?? this.title,
    rules: rules ?? this.rules,
  );

  factory Panel.fromJson(Map<Object?, Object?> json) {
    final id = jsonRequired<String>(json, 'id');
    return Panel(
      id: id,
      title: jsonOptional<String>(json, 'title') ?? '',
      root: switch (jsonOptional<Map<Object?, Object?>>(json, 'pane')) {
        final pane? => Pane.fromJson(pane),
        null => _emptyRoot(id),
      },
      rules: {...?jsonOptional<Map<Object?, Object?>>(json, 'rules')?.cast()},
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (rules.isNotEmpty) 'rules': rules,
    'pane': root.toJson(),
  };
}
