/// Where a panel is shown, decided by its id: home, a sidebar id, or anything
/// else (a popup).
enum PanelKind { home, sidebar, popup }

/// How a pane arranges its children.
enum PaneMode {
  /// In order, wrapping at the last column.
  flow,

  /// At explicit cells; gaps allowed.
  grid,

  /// Anywhere, at fractional cell sizes; may overlap, later on top.
  free,

  /// In a row, sized by flex and aspect.
  row,

  /// In a column, likewise.
  column;

  bool get inLine => this == row || this == column;
}

enum BarEdge { left, right, top, bottom }
