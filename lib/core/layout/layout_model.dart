import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
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
  /// other entity. The pane is placed to leave the screen's margins and
  /// the room at the top, and reaches the bottom: new apps turn up in it,
  /// and it scrolls when they do not fit.
  factory Layout.initial([List<String> order = const []]) => Layout(
    inbox: _firstPane,
    panels: [
      Panel(
        id: homeId,
        root: Component.pane(
          id: Panel.rootId(homeId),
          mode: PaneMode.free,
          columns: Component.globalColumns,
          children: [
            Component.pane(
              id: _firstPane,
              x: 0.59,
              y: 1.35,
              w: 10.82,
              h: 7.69,
              children: [
                for (final id in order)
                  Component.of(id, id: Component.autoId(id)),
              ],
            ),
          ],
        ),
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

  /// The sidebars there are, whether or not anything is in them.
  Iterable<Panel> get bars => [for (final id in barIds) ?panel(id)];

  /// The id of the folder [item] was handed, where it is an instance of a
  /// prefab handed one: what opens a folder.
  String? folderOf(Component item) => !item.isInstance
      ? null
      : item.handed
            .where((id) => panel(id)?.kind == PanelKind.popup)
            .firstOrNull;

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
    List<Component> Function(Component pane, List<Component> items) change, {
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
        if (!item.isInstance || !item.handed.any(entityIds.contains)) item,
    ],
    removed: {...removed, ...entityIds},
  );
}
