import 'package:openlauncher/core/layout/layout_item.dart';
import 'package:openlauncher/core/layout/layout_model.dart';

/// Where a panel is shown. Decided by the panel's id: [Layout.homeId] is the
/// main screen, [Layout.leftId] and [Layout.rightId] are the rails on the
/// screen edges, and every other panel is a popup opened from a card.
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
  /// An app, input or launcher action; [LayoutItem.ref] is the card id.
  card,

  /// Opens a popup panel (this is what a folder is); [LayoutItem.ref] is the
  /// panel id.
  panel,

  /// A launcher widget; [LayoutItem.ref] is the `WidgetKind` name.
  widget,

  /// A pane inside this one, held in [LayoutItem.pane].
  pane,
}

/// How a card or a folder is drawn: its picture with its name under it, or
/// as a row, its picture with its name beside it.
enum TileLook { card, row }

/// The edge of the screen a sidebar is on.
enum BarEdge { left, right, top, bottom }

/// How a sidebar comes open: growing out from its edge over what is in it,
/// sliding in whole, fading in where it will be, or at once.
enum BarOpening { expand, slide, fade, instant }

/// How what is in a sidebar appears: there all along, fading in as the
/// sidebar opens, fading in once it is open, or sliding in from its edge.
enum BarReveal { always, fade, late, slide }

enum PopupPosition { center, bottom, left, right }

enum PopupSize { small, medium, large }
