import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether [key] is one of the remote's "OK" buttons.
bool isSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

/// Something the D-pad can land on. A press selects it; holding the button
/// down (or pressing Menu) asks for its menu instead.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.builder,
    required this.onSelect,
    this.onMenu,
    this.autofocus = false,
    this.focusedScale = 1.08,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;

  /// Called with true when the menu was asked for by holding OK, in which
  /// case the button is still down.
  final void Function(bool held)? onMenu;
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
    if (!focused) {
      _cancelHold();
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: FocusTile.duration,
      curve: Curves.easeOut,
    );
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
