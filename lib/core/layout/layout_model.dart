import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/legacy_sections.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';

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
        root: paneFromSections(homeId, [
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
    panels: jsonList(
      json,
      'panels',
      (panel) => Panel.fromJson(
        panel,
        barsFromBefore: (jsonOptional<num>(json, 'v') ?? 1) < _version,
      ),
    ),
    inbox: jsonOptional<String>(json, 'inbox') ?? '',
    removed: {
      ...?jsonOptional<List<Object?>>(json, 'removed')?.whereType<String>(),
    },
  );

  Map<String, Object?> toJson() => {
    'v': _version,
    'inbox': inbox,
    'removed': removed.toList(),
    'panels': [for (final panel in panels) panel.toJson()],
  };

  /// A copy in which the items of every pane on every panel have been
  /// replaced by what [change] returns for them.
  Layout rebuild(
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
  Layout without(Set<String> cardIds) => rebuild(
    (_, items) => [
      for (final item in items)
        if (item.kind != ItemKind.card || !cardIds.contains(item.ref)) item,
    ],
    removed: {...removed, ...cardIds},
  );
}
