import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/panel.dart';

/// The saved layout.
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

  /// The quick-actions popup.
  static const menuId = 'quick-actions';

  static const barIds = [leftId, rightId, topId, bottomId];

  static const _firstPane = 'main';

  /// A home screen with one full-height pane holding [order].
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

  /// The pane that receives unplaced entities, e.g. new apps.
  final String inbox;

  /// Entities the user removed; they are not put back in the [inbox].
  final Set<String> removed;

  Panel get home => panel(homeId)!;

  Panel? panel(String id) {
    for (final panel in panels) {
      if (panel.id == id) return panel;
    }
    return null;
  }

  Iterable<Panel> get bars => [for (final id in barIds) ?panel(id)];

  /// The folder [item] opens, if it is an instance handed one.
  String? folderOf(Component item) => !item.isInstance
      ? null
      : item.handed
            .where((id) => panel(id)?.kind == PanelKind.popup)
            .firstOrNull;

  /// Throws [FormatException] on malformed JSON. Older versions are migrated
  /// first. The result still needs [normalised].
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

  /// Rebuilds every pane's children with [change].
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

  /// Removes [entityIds] from every panel and marks them [removed].
  Layout without(Set<String> entityIds) => rebuild(
    (_, items) => [
      for (final item in items)
        if (!item.isInstance || !item.handed.any(entityIds.contains)) item,
    ],
    removed: {...removed, ...entityIds},
  );
}
