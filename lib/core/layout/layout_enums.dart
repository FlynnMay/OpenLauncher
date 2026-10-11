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

  /// A launcher widget; [LayoutItem.ref] is the `WidgetKind` name.
  widget,

  /// A pane inside this one, held in [LayoutItem.pane].
  pane,
}

/// The edge of the screen a sidebar is on.
enum BarEdge { left, right, top, bottom }

/// How a sidebar comes open: growing out from its edge over what is in it,
/// sliding in whole, fading in where it will be, or at once.
enum BarOpening { expand, slide, fade, instant }

/// How what is in a sidebar appears: there all along, fading in as the
/// sidebar opens, fading in once it is open, or sliding in from its edge.
enum BarReveal { always, fade, late, slide }

/// Where what a folder holds shows when it is opened: hovering over the
/// screen at one of four places, or in place, where the folder itself is.
enum PopupPosition { center, bottom, left, right, inline }

enum PopupSize { small, medium, large }
