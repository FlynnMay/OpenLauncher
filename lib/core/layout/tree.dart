import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// What comes of a node's modules together: the panes in it, whether it
/// scrolls, what its children are drawn as.
extension NodeTree on Node {
  /// This pane and every pane inside it, the nodes holding an instance's
  /// slots among them.
  Iterable<Node> get panes sync* {
    if (isPane) {
      yield this;
    } else if (!isInstance) {
      return;
    }
    for (final child in children) {
      yield* child.panes;
    }
  }

  /// This pane and the panes on its cells, skipping docked ones.
  Iterable<Node> get cellPanes sync* {
    if (isPane) {
      yield this;
    } else if (!isInstance) {
      return;
    }
    for (final child in children) {
      if (!child.isDocked) yield* child.cellPanes;
    }
  }

  /// Every node in this pane and the panes inside it that is not a pane, or
  /// an instance that docks.
  Iterable<Node> get contents => panes
      .expand((pane) => pane.children)
      .where((child) => !child.isPane && !child.isDocked);

  /// The same, skipping what is in docked panes.
  Iterable<Node> get ownContents => cellPanes
      .expand((pane) => pane.children)
      .where((child) => !child.isPane && !child.isDocked);

  /// True if it holds nothing but empty panes.
  bool get isEmpty => children.every((child) => child.isPane && child.isEmpty);

  /// Rebuilds every pane's children with [change], innermost first. What an
  /// instance holds in its slots is rebuilt too, but not the instance.
  Node rebuild(List<Node> Function(Node pane, List<Node> children) change) {
    if (isInstance && children.isNotEmpty) {
      return copyWith(
        children: [for (final holder in children) holder.rebuild(change)],
      );
    }
    return !isPane
        ? this
        : copyWith(
            children: change(this, [
              for (final child in children) child.rebuild(change),
            ]),
          );
  }

  bool get _fitted => mode.inLine && fit;

  /// Whether it scrolls across: a row, or cells, that ask to. Cells then
  /// stop wrapping at [columns].
  bool get scrollsAcross =>
      wantsAcross &&
      mode != PaneMode.column &&
      mode != PaneMode.free &&
      !_fitted;

  /// Whether it scrolls down: cells, or a column, that ask to.
  bool get scrollsDown =>
      wantsDown && mode != PaneMode.row && mode != PaneMode.free && !_fitted;

  /// What shows how far it is scrolled: `thumb`, `progress`, or null.
  String? get scrollbar => scrollsAcross || scrollsDown ? wantsBar : null;

  /// The columns its children can be placed on.
  int get reach => scrollsAcross ? LayoutModule.maxReach : columns;

  /// Whether it overrides anything on its children.
  bool get decides => itemW != null || itemH != null || prefabRules.isNotEmpty;

  /// The children with its rules applied; what is drawn.
  List<Node> get shown {
    if (!decides) return children;
    final rules = prefabRules;
    return [
      for (final child in children)
        if (child.isInstance)
          switch (child.underRule(rules[child.prefab])) {
            final ruled => ruled.sized(
              itemW ?? ruled.w,
              itemH ?? ruled.h,
              x: ruled.x,
              y: ruled.y,
            ),
          }
        else
          child,
    ];
  }
}
