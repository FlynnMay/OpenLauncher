import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// What comes of a node's modules together: the containers in it, whether it
/// scrolls, what its children are drawn as.
extension NodeTree on Node {
  /// This node and every node inside it that can hold others: any but an
  /// instance, whose slots' nodes are among them.
  Iterable<Node> get containers sync* {
    if (!isInstance) yield this;
    for (final child in children) {
      yield* child.containers;
    }
  }

  /// The same, skipping docked ones.
  Iterable<Node> get cellContainers sync* {
    if (!isInstance) yield this;
    for (final child in children) {
      if (!child.isDocked) yield* child.cellContainers;
    }
  }

  /// Every node in this container and the containers inside it that is not a
  /// container, or an instance that docks.
  Iterable<Node> get contents => containers
      .expand((container) => container.children)
      .where((child) => !child.isContainer && !child.isDocked);

  /// The same, skipping what is in docked containers.
  Iterable<Node> get ownContents => cellContainers
      .expand((container) => container.children)
      .where((child) => !child.isContainer && !child.isDocked);

  /// True if it holds nothing but empty containers.
  bool get isEmpty =>
      children.every((child) => child.isContainer && child.isEmpty);

  /// Rebuilds every container's children with [change], innermost first. What
  /// an instance holds in its slots is rebuilt too, but not the instance.
  Node rebuild(
    List<Node> Function(Node container, List<Node> children) change,
  ) {
    if (isInstance && children.isNotEmpty) {
      return copyWith(
        children: [for (final holder in children) holder.rebuild(change)],
      );
    }
    return isInstance
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
      mode != LayoutMode.column &&
      mode != LayoutMode.free &&
      !_fitted;

  /// Whether it scrolls down: cells, or a column, that ask to.
  bool get scrollsDown =>
      wantsDown &&
      mode != LayoutMode.row &&
      mode != LayoutMode.free &&
      !_fitted;

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
