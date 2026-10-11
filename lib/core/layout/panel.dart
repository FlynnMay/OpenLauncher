import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/rules.dart';

/// A surface: the home screen, a sidebar or a popup. Its content is [root].
@immutable
class Panel {
  const Panel({
    required this.id,
    required this.root,
    this.title = '',
    this.rules = const {},
  });

  Panel.empty(this.id, {this.title = '', this.rules = const {}})
    : root = _emptyRoot(id);

  /// A sidebar dimension that fills the screen.
  static const fill = double.infinity;

  /// Largest sidebar size, in TV pixels.
  static const maxExtent = 960.0;

  final String id;

  /// A popup's heading, and the label of cards that open it.
  final String title;

  final Component root;

  /// Settings described by [panelRules], plus a sidebar's `width`, `height`
  /// and `closed` in TV pixels (`fill` for all of it). Unset means default.
  final Map<String, Object?> rules;

  /// The rule's value, or its default.
  Object? rule(String key) =>
      rules[key] ??
      panelRules(kind).where((rule) => rule.key == key).firstOrNull?.usual;

  /// Sets a rule; null restores the default.
  Panel withRule(String key, Object? value) => copyWith(
    rules: {...rules, key: value == fill ? 'fill' : value}
      ..removeWhere((_, value) => value == null),
  );

  double? _extent(String key) => switch (rules[key]) {
    'fill' => fill,
    final num size => size.toDouble(),
    _ => null,
  };

  /// Open size of a sidebar; null for the edge's default.
  double? get width => _extent('width');
  double? get height => _extent('height');

  /// How much of a closed sidebar shows; 0 hides it.
  double? get closed => _extent('closed');

  BarEdge? get edge => edgeOf(id);

  static BarEdge? edgeOf(String id) => switch (id) {
    Layout.leftId => BarEdge.left,
    Layout.rightId => BarEdge.right,
    Layout.topId => BarEdge.top,
    Layout.bottomId => BarEdge.bottom,
    _ => null,
  };

  /// True for the left and right edges.
  bool get opensAcross => edge == BarEdge.left || edge == BarEdge.right;

  /// Defaults per edge: side bars are full height and closed to a strip; top
  /// and bottom bars are full width and hidden when closed.
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

  /// The `iconOverrides` key for a folder's picture.
  static String iconKey(String panelId) => 'panel:$panelId';

  static Component _emptyRoot(String panelId) => switch (kindOf(panelId)) {
    PanelKind.home => Component.pane(
      id: rootId(panelId),
      mode: PaneMode.grid,
      columns: Component.globalColumns,
    ),
    // Side bars are one column of rows; top and bottom bars are one row.
    PanelKind.sidebar => switch (edgeOf(panelId)) {
      BarEdge.top ||
      BarEdge.bottom => Component.pane(id: rootId(panelId), columns: 8),
      _ => Component.pane(id: rootId(panelId), columns: 1).asBar(),
    },
    PanelKind.popup => Component.pane(id: rootId(panelId), columns: 4),
  };

  /// Every non-pane component on the panel.
  Iterable<Component> get items => root.contents;

  bool get isEmpty => root.isEmpty;

  Panel withRoot(Component root) => copyWith(root: root);

  Panel copyWith({
    String? id,
    Component? root,
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
      root: switch (jsonOptional<Map<Object?, Object?>>(json, 'root')) {
        final pane? => Component.fromJson(pane),
        null => _emptyRoot(id),
      },
      rules: {...?jsonOptional<Map<Object?, Object?>>(json, 'rules')?.cast()},
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (rules.isNotEmpty) 'rules': rules,
    'root': root.toJson(),
  };
}
