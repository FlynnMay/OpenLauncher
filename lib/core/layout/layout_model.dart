import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
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

  /// The popup a held entity opens: the quick actions, a button for each.
  static const menuId = 'quick-actions';

  /// The ids of the sidebars there can be, one for each edge.
  static const barIds = [leftId, rightId, topId, bottomId];

  static const _firstPane = 'main';

  /// The home screen with one pane showing [order] first and then every
  /// other entity.
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
                LayoutItem.of(id, id: LayoutItem.autoId(id)),
            ],
          ),
        ]),
      ),
    ],
  );

  final List<Panel> panels;

  /// The pane that shows entities not placed anywhere, such as newly installed
  /// apps.
  final String inbox;

  /// Entities the user took off the screen altogether. They are not put back
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
  ///
  /// A layout saved by an older version is brought up to date first, by
  /// the steps in `core/config/migrations`; only what is written now is
  /// read here.
  factory Layout.fromJson(Map<Object?, Object?> saved) {
    final json = migrateLayout(saved);
    return Layout(
      panels: jsonList(json, 'panels', Panel.fromJson),
      inbox: jsonOptional<String>(json, 'inbox') ?? '',
      removed: {
        ...?jsonOptional<List<Object?>>(json, 'removed')?.whereType<String>(),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'v': saveVersion,
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

  /// A copy with every entity in [entityIds] taken off all panels and noted as
  /// [removed].
  Layout without(Set<String> entityIds) => rebuild(
    (_, items) => [
      for (final item in items)
        if (item.kind != ItemKind.prefab || !entityIds.contains(item.source))
          item,
    ],
    removed: {...removed, ...entityIds},
  );
}
