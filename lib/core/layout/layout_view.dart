import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';
import 'package:openlauncher/core/layout/layout_repair.dart';
import 'package:openlauncher/core/layout/pane.dart';
import 'package:openlauncher/core/layout/panel.dart';

/// A layout item together with what it shows.
@immutable
sealed class Entry {
  const Entry(this.item);

  final LayoutItem item;
}

class EntityEntry extends Entry {
  const EntityEntry(super.item, this.entity);

  final Entity entity;
}

/// An entity that opens a popup: a folder, or any other panel.
class PanelEntry extends Entry {
  const PanelEntry(
    super.item,
    this.panel, {
    this.preview = const [],
    this.icon,
  });

  final Panel panel;

  /// The first few entities inside, for drawing the folder's face.
  final List<Entity> preview;

  /// A picture the user chose for it, as an absolute path.
  final String? icon;

  String get label => panel.title.isEmpty ? 'Folder' : panel.title;

  /// The key of a panel entity's picture in `LauncherConfig.iconOverrides`.
  static String iconKey(String panelId) => 'panel:$panelId';
}

class WidgetEntry extends Entry {
  const WidgetEntry(super.item);
}

/// A pane inside another, with what is in it.
class PaneEntry extends Entry {
  const PaneEntry(super.item, this.view);

  final PaneView view;
}

/// A pane with each of its items matched to what it shows.
@immutable
class PaneView {
  const PaneView(this.pane, this.entries);

  final Pane pane;

  /// One per item of [pane], in order.
  final List<Entry> entries;

  /// Everything in this pane and the panes inside it, other than the panes
  /// themselves.
  Iterable<Entry> get contents => entries.expand(
    (entry) => entry is PaneEntry ? entry.view.contents : [entry],
  );

  /// Whether there is nothing in it but, at most, empty panes.
  bool get isEmpty =>
      entries.every((entry) => entry is PaneEntry && entry.view.isEmpty);
}

@immutable
class PanelView {
  const PanelView(this.panel, this.root);

  final Panel panel;

  /// The pane that fills the panel.
  final PaneView root;

  bool get isEmpty => root.isEmpty;
}

/// The layout with every item matched to the entity, panel, widget or pane it
/// stands for: what the TV draws.
@immutable
class LayoutView {
  const LayoutView(this.panels);

  final Map<String, PanelView> panels;

  PanelView get home => panels[Layout.homeId]!;

  /// The sidebars there are, whether or not anything is in them.
  Iterable<PanelView> get bars => [for (final id in Layout.barIds) ?panels[id]];
}

const _previewCount = 4;

/// [layout] matched to the [entities] there are: what is drawn from one
/// that is gone is dropped, and those of a kind that is put on the screen
/// of itself, placed nowhere, are in the inbox.
Layout layoutWith(Layout layout, List<Entity> entities) => layout.withEntities(
  [
    for (final entity in entities)
      if (entityKind(entity.kind)?.prefab != null) entity.id,
  ],
  known: {for (final entity in entities) entity.id},
  names: {for (final entity in entities) entity.id: entity.sourceLabel},
);

/// Matches [config]'s layout against the [entities] there are. Entities placed
/// nowhere appear in the inbox pane, unless the user removed them.
LayoutView resolveLayout(List<Entity> entities, LauncherConfig config) {
  final byId = {for (final entity in entities) entity.id: entity};
  final layout = layoutWith(config.layout, entities);

  List<Entity> preview(Panel panel) => [
    for (final item in panel.items)
      if (item.kind == ItemKind.prefab) byId[item.source]!,
  ].take(_previewCount).toList();

  late PaneView Function(Pane) view;
  Entry entry(LayoutItem item) => switch (item.kind) {
    ItemKind.prefab => EntityEntry(item, byId[item.source]!),
    ItemKind.widget => WidgetEntry(item),
    ItemKind.pane => PaneEntry(item, view(item.pane!)),
    ItemKind.panel => () {
      final panel = layout.panel(item.ref)!;
      return PanelEntry(
        item,
        panel,
        preview: preview(panel),
        icon: config.iconOverrides[PanelEntry.iconKey(panel.id)],
      );
    }(),
  };
  // Drawn as the pane would have them: see [Pane.shown].
  view = (pane) {
    final shown = pane.withItems(pane.shown);
    return PaneView(shown, shown.items.map(entry).toList());
  };

  return LayoutView({
    for (final panel in layout.panels)
      panel.id: PanelView(panel, view(panel.root)),
  });
}

/// The layout as the TV shows it, kept current with the device and config.
final layoutViewProvider = FutureProvider<LayoutView>((ref) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  return resolveLayout(entities, config);
});
