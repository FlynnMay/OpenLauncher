import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:openlauncher/features/modules/scroll_drawer.dart';

/// Whether [key] is one of the remote's "OK" buttons.
bool isSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

/// A focusable tile. OK selects; holding OK or pressing Menu opens its menu.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.builder,
    required this.onSelect,
    this.onMenu,
    this.onFocus,
    this.autofocus = false,
    this.focusedScale = 1.08,
    this.still = false,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;

  /// [held] is true when OK is still down.
  final void Function(bool held)? onMenu;

  final void Function(bool focused)? onFocus;
  final bool autofocus;
  final double focusedScale;

  /// Takes the focus but does nothing when pressed; the editor selects with
  /// the press instead.
  final bool still;

  static const duration = Duration(milliseconds: 150);
  static const holdTime = Duration(milliseconds: 500);

  @override
  State<FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<FocusTile> {
  bool _focused = false;

  /// Running while OK is down but not yet held long enough.
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

  /// Margin kept around a tile when scrolling to it, for its focused size.
  static const _overhang = 12.0;

  /// Scrolls the tile into view. A layer's root centres it; a pane scrolls
  /// as little as needed, showing the top of a tile taller than itself.
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
    for (final scrollable in around) {
      final position = scrollable.position;
      if (scrollable.widget.controller is ScreenScrollController ||
          viewport == null) {
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
    if (widget.still) return KeyEventResult.ignored;
    final onMenu = widget.onMenu;
    if (event.logicalKey == LogicalKeyboardKey.contextMenu && onMenu != null) {
      if (event is KeyDownEvent) onMenu(false);
      return KeyEventResult.handled;
    }
    if (!isSelectKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // Select fires on release so a hold can become the menu.
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
    final onMenu = widget.still ? null : widget.onMenu;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.still ? null : widget.onSelect,
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
