import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// The containers the widgets below are in, outermost first; used by focus
/// navigation.
class ContainerScope extends InheritedWidget {
  const ContainerScope({
    super.key,
    required this.containers,
    required super.child,
  });

  final List<String> containers;

  static List<String> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ContainerScope>()
          ?.containers ??
      const [];

  /// The same without subscribing.
  static List<String> peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ContainerScope>()?.containers ??
      const [];

  @override
  bool updateShouldNotify(ContainerScope oldWidget) =>
      !listEquals(containers, oldWidget.containers);
}

/// The visible part of the widgets below when it is less than their layout,
/// e.g. a closed sidebar. Navigation uses it.
class FocusBounds extends InheritedWidget {
  const FocusBounds({super.key, required this.visible, required super.child});

  /// In global coordinates.
  final Rect? Function() visible;

  @override
  bool updateShouldNotify(FocusBounds oldWidget) => false;
}

/// Where [node] is visible. If fully hidden, a point on the edge it is
/// behind.
Rect focusRect(FocusNode node) {
  final rect = node.rect;
  final bounds = node.context
      ?.getInheritedWidgetOfExactType<FocusBounds>()
      ?.visible();
  if (bounds == null) return rect;
  return Rect.fromLTRB(
    rect.left.clamp(bounds.left, bounds.right),
    rect.top.clamp(bounds.top, bounds.bottom),
    rect.right.clamp(bounds.left, bounds.right),
    rect.bottom.clamp(bounds.top, bounds.bottom),
  );
}

/// Moves the focus using [navigate] (same container first, then inside, around,
/// anywhere). It does not scroll to the target; [FocusTile] does that itself.
class TileTraversal extends StatelessWidget {
  const TileTraversal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: _ContainerPolicy(), child: child);
}

class _ContainerPolicy extends ReadingOrderTraversalPolicy {
  _ContainerPolicy() : super(requestFocusCallback: _focusOnly);

  static void _focusOnly(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) => node.requestFocus();

  static NavSpot<FocusNode> _spot(FocusNode node) =>
      NavSpot(node, focusRect(node), switch (node.context) {
        null => const [],
        final context => ContainerScope.peek(context),
      });

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    // Nothing has the focus yet: let Flutter pick where to start.
    if (scope == null || currentNode == scope) {
      return super.inDirection(currentNode, direction);
    }
    final target = navigate(
      _spot(currentNode),
      [
        for (final node in scope.traversalDescendants)
          if (node != currentNode && node.canRequestFocus) _spot(node),
      ],
      switch (direction) {
        TraversalDirection.left => NavDirection.left,
        TraversalDirection.right => NavDirection.right,
        TraversalDirection.up => NavDirection.up,
        TraversalDirection.down => NavDirection.down,
      },
    );
    if (target == null) return false;
    target.id.requestFocus();
    return true;
  }
}
