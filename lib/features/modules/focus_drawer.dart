import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/modules/focus_tile.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';

/// Gives the initial focus to the first tile that asks.
class FirstFocus {
  bool _taken = false;

  /// True once only.
  bool take() => !_taken && (_taken = true);
}

/// Whether the tile the widgets below belong to has the focus.
class TileFocus extends InheritedWidget {
  const TileFocus({super.key, required this.focused, required super.child});

  final bool focused;

  static bool? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileFocus>()?.focused;

  @override
  bool updateShouldNotify(TileFocus oldWidget) => focused != oldWidget.focused;
}

/// The part of the focusable node above that shows its focus, and how.
class FocusTarget extends InheritedWidget {
  const FocusTarget({
    super.key,
    required this.ids,
    required this.box,
    required this.bare,
    required super.child,
  });

  /// The target as named in its prefab and as resolved in an instance.
  final Set<String> ids;

  /// The focusable node's box, which the target paints.
  final BoxStyle box;

  /// No background, only a faint wash when focused.
  final bool bare;

  static FocusTarget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusTarget>();

  @override
  bool updateShouldNotify(FocusTarget oldWidget) =>
      !setEquals(ids, oldWidget.ids) ||
      box != oldWidget.box ||
      bare != oldWidget.bare;
}

/// [box] painted around [child] with the focus shown: a white border while
/// focused, and with no fill a surface, or a faint wash when [bare].
class FocusFrame extends StatelessWidget {
  const FocusFrame({
    super.key,
    required this.box,
    required this.child,
    this.bare = false,
    this.corner = 10,
  });

  final BoxStyle box;
  final Widget child;
  final bool bare;

  /// Corner radius when [box] sets none.
  final double corner;

  @override
  Widget build(BuildContext context) {
    final focused = TileFocus.of(context) ?? false;
    final fill = styleFill(box);
    final outline = box.border;
    final shape = styleShape(box, corner);
    return AnimatedContainer(
      duration: FocusTile.duration,
      clipBehavior: Clip.antiAlias,
      // The border is drawn over the content so focus does not resize the
      // tile.
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(
          color: focused
              ? Colors.white
              : outline == null
              ? Colors.transparent
              : Color(outline),
          width: outline == null ? 2 : box.borderWidth,
        ),
      ),
      decoration: BoxDecoration(
        gradient: fill.gradient,
        color: fill.gradient != null
            ? null
            : fill.color ??
                  (!bare
                      ? Theme.of(context).colorScheme.surfaceContainerHigh
                      : focused
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.transparent),
        borderRadius: shape,
        boxShadow: styleShadow(box),
      ),
      child: child,
    );
  }
}

/// What the remote does to a focusable node.
typedef RemoteCalls = ({
  VoidCallback press,
  void Function(bool held)? hold,
  void Function(bool focused)? focus,
});

/// [child] focusable as [node]'s Focus says: it grows when focused, and its
/// box, [box], shows the focus around it, or around its target part.
class FocusView extends StatelessWidget {
  const FocusView({
    super.key,
    required this.node,
    required this.box,
    required this.bare,
    required this.calls,
    required this.child,
    this.corner = 10,
    this.autofocus = false,
    this.still = false,
  });

  final Node node;
  final BoxStyle box;

  /// [Node.focusBare] read.
  final bool bare;

  final RemoteCalls calls;
  final Widget child;

  /// Corner radius when [box] sets none.
  final double corner;

  final bool autofocus;

  /// Takes the focus but does nothing when pressed.
  final bool still;

  @override
  Widget build(BuildContext context) {
    final target = node.focusTarget;
    return FocusTile(
      autofocus: autofocus,
      still: still,
      focusedScale: node.focusScale,
      onSelect: calls.press,
      onMenu: calls.hold,
      onFocus: calls.focus,
      builder: (context, focused) => TileFocus(
        focused: focused,
        child: target != null
            ? FocusTarget(
                ids: {target, '${node.id}/$target'},
                box: box,
                bare: bare,
                child: child,
              )
            : FocusFrame(box: box, bare: bare, corner: corner, child: child),
      ),
    );
  }
}
