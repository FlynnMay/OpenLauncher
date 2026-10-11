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

  /// Side by side in a line, each taking the room its transform says:
  /// what a card is made with.
  row,

  /// The same, one under the other.
  column;

  /// Whether it puts things in a line rather than on cells.
  bool get inLine => this == row || this == column;
}

/// The edge of the screen a sidebar is on.
enum BarEdge { left, right, top, bottom }
