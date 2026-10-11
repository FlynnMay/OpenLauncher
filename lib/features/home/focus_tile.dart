import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Whether [key] is one of the remote's "OK" buttons.
bool isSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

/// Says which panes the widgets below it are in, outermost first, so that
/// moving the focus can prefer what is in the same pane.
class PaneScope extends InheritedWidget {
  const PaneScope({super.key, required this.panes, required super.child});

  final List<String> panes;

  static List<String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>()?.panes ??
      const [];

  /// The same, for a context that is only being looked at, not built.
  static List<String> peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PaneScope>()?.panes ?? const [];

  @override
  bool updateShouldNotify(PaneScope oldWidget) =>
      !listEquals(panes, oldWidget.panes);
}

/// Says how much of the widgets below it can be seen, when that is less
/// than where they are laid out: a sidebar that is closed to a strip, or
/// out of sight. Moving the focus goes by what can be seen.
class FocusBounds extends InheritedWidget {
  const FocusBounds({super.key, required this.visible, required super.child});

  /// What is in view, in the coordinates of the whole display.
  final Rect? Function() visible;

  @override
  bool updateShouldNotify(FocusBounds oldWidget) => false;
}

/// Where on the display [node] can be seen: where it is, cut down to what
/// its [FocusBounds] let through. Wholly out of view, it is a point on the
/// edge it is behind, which is where the focus has to go to reach it.
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

/// Moves the focus between tiles the launcher's way.
///
/// Where a press of the D-pad leads is decided by [navigate]: what is in the
/// same pane first, then in a pane inside it, then around it, then anywhere.
///
/// It also does not scroll to what it focuses. Flutter's own handling
/// scrolls every scrollable around the newly focused widget, to its end when
/// moving right or down and to its start when moving left or up; a
/// [FocusTile] decides for itself how it comes into view, and two rules
/// pulling in turn made panes jump.
class TileTraversal extends StatelessWidget {
  const TileTraversal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: _PanePolicy(), child: child);
}

class _PanePolicy extends ReadingOrderTraversalPolicy {
  _PanePolicy() : super(requestFocusCallback: _focusOnly);

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
        final context => PaneScope.peek(context),
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

/// Something the D-pad can land on. A press selects it; holding the button
/// down (or pressing Menu) asks for its menu instead.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.builder,
    required this.onSelect,
    this.onMenu,
    this.onFocus,
    this.autofocus = false,
    this.focusedScale = 1.08,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;

  /// Called with true when the menu was asked for by holding OK, in which
  /// case the button is still down.
  final void Function(bool held)? onMenu;

  /// Called as the focus arrives (true) and as it leaves.
  final void Function(bool focused)? onFocus;
  final bool autofocus;
  final double focusedScale;

  static const duration = Duration(milliseconds: 150);
  static const holdTime = Duration(milliseconds: 500);

  @override
  State<FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<FocusTile> {
  bool _focused = false;

  /// Running while OK is down and has not yet been held long enough.
  Timer? _hold;

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    widget.onFocus?.call(focused);
    if (!focused) {
      _cancelHold();
      return;
    }
    _reveal();
  }

  /// Room left around a tile when a pane scrolls to it: enough for it to
  /// grow and show its outline when focused.
  static const _overhang = 12.0;

  /// Scrolls whatever needs scrolling for this tile to be seen. The screen
  /// brings it to the middle. A pane inside the screen moves only as far as
  /// it must, so its contents do not shift about as the focus moves in it;
  /// if the tile is taller than the pane, its top is what shows.
  void _reveal() {
    final object = context.findRenderObject();
    if (object == null) return;
    final around = <ScrollableState>[];
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    ) {
      around.add(scrollable);
    }
    // Each scrollable has one viewport, nested the same way.
    var viewport = RenderAbstractViewport.maybeOf(object);
    for (final (index, scrollable) in around.indexed) {
      final position = scrollable.position;
      if (index == around.length - 1 || viewport == null) {
        position.ensureVisible(
          object,
          alignment: 0.5,
          duration: FocusTile.duration,
          curve: Curves.easeOut,
        );
        break;
      }
      final top = viewport.getOffsetToReveal(object, 0).offset - _overhang;
      final bottom = viewport.getOffsetToReveal(object, 1).offset + _overhang;
      final fits = bottom <= top;
      // How far down the pane the tile starts, as things are.
      final from = top + _overhang - position.pixels;
      final target = top < position.pixels
          ? top
          : fits && bottom > position.pixels
          ? bottom
          // Too tall to fit: bring its top up, unless it is already near it.
          : !fits && from > position.viewportDimension / 2
          ? top
          : position.pixels;
      final within = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (within != position.pixels) {
        position.animateTo(
          within,
          duration: FocusTile.duration,
          curve: Curves.easeOut,
        );
      }
      viewport = RenderAbstractViewport.maybeOf(
        (viewport as RenderObject).parent,
      );
    }
  }

  void _cancelHold() {
    _hold?.cancel();
    _hold = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final onMenu = widget.onMenu;
    if (event.logicalKey == LogicalKeyboardKey.contextMenu && onMenu != null) {
      if (event is KeyDownEvent) onMenu(false);
      return KeyEventResult.handled;
    }
    if (!isSelectKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // Selecting waits for the release, so a hold can become the menu.
      _hold = Timer(FocusTile.holdTime, () {
        _hold = null;
        (onMenu ?? (_) => widget.onSelect())(true);
      });
    } else if (event is KeyUpEvent && _hold != null) {
      _cancelHold();
      widget.onSelect();
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onMenu = widget.onMenu;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onSelect,
        onLongPress: onMenu == null ? null : () => onMenu(false),
        onSecondaryTap: onMenu == null ? null : () => onMenu(false),
        child: AnimatedScale(
          scale: _focused ? widget.focusedScale : 1,
          duration: FocusTile.duration,
          curve: Curves.easeOut,
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}
