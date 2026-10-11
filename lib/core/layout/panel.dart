import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/pane.dart';

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

  /// Shown as the heading of a popup and as the label of entities opening it.
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

  static const _keep = Object();

  /// This panel with some of its settings changed. [width], [height] and
  /// [closed] may be given as null, for the usual ones.
  Panel copyWith({
    String? id,
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
    id: id ?? this.id,
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

  factory Panel.fromJson(Map<Object?, Object?> json) {
    final id = jsonRequired<String>(json, 'id');
    return Panel(
      id: id,
      title: jsonOptional<String>(json, 'title') ?? '',
      root: switch (jsonOptional<Map<Object?, Object?>>(json, 'pane')) {
        final pane? => Pane.fromJson(pane),
        null => _emptyRoot(id),
      },
      position: jsonNamed(
        PopupPosition.values,
        jsonOptional<String>(json, 'position'),
        PopupPosition.center,
      ),
      size: jsonNamed(
        PopupSize.values,
        jsonOptional<String>(json, 'size'),
        PopupSize.medium,
      ),
      width: _extent(json, 'width'),
      height: _extent(json, 'height'),
      closed: jsonOptional<num>(json, 'closed')?.toDouble(),
      opening: jsonNamed(
        BarOpening.values,
        jsonOptional<String>(json, 'opening'),
        BarOpening.expand,
      ),
      reveal: jsonNamed(
        BarReveal.values,
        jsonOptional<String>(json, 'reveal'),
        BarReveal.always,
      ),
    );
  }

  static Object? _written(double? extent) => switch (extent) {
    null => null,
    fill => 'fill',
    final size => tidy(size),
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
}
