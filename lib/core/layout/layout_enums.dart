import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';

/// Where a panel is shown. Decided by the panel's id: [Layout.homeId] is the
/// main screen, [Layout.leftId] and [Layout.rightId] are the rails on the
/// screen edges, and every other panel is a popup opened from an entity.
enum PanelKind { home, sidebar, popup }

/// How a pane positions its items on its cell grid.
enum PaneMode {
  /// One after another, wrapping at the last column.
  flow,

  /// Each item at its own column and row; gaps are allowed.
  grid,

  /// Each item anywhere, at any size, measured in cells but not held to
  /// them. Items may overlap; later ones are drawn on top.
  free,
}

enum ItemKind {
  /// An instance of a prefab: [LayoutItem.ref] is the prefab's id and
  /// [LayoutItem.source] the id of the entity it is drawn from. What used
  /// to be called a card is one of these, of the prefab `app-card`; what
  /// opens a folder is one of `folder-card`, drawn from the folder.
  prefab,

  /// One of the launcher's own components; [LayoutItem.ref] is the
  /// `ComponentKind` name.
  component,

  /// A pane inside this one, held in [LayoutItem.pane].
  pane,
}

/// The edge of the screen a sidebar is on.
enum BarEdge { left, right, top, bottom }
