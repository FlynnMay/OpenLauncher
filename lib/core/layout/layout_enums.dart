/// How a pane arranges its children.
enum LayoutMode {
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

/// A screen edge a pane can be docked to.
enum BarEdge { left, right, top, bottom }
