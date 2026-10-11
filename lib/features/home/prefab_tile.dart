import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/features/widgets/widget_tile.dart';

/// An instance of a prefab as a tile: its parts, arranged as its layout
/// says, reading its variables ([scope]) for whatever they are written
/// against. One that
/// does something when pressed or held can be landed on; the part marked
/// `frame` is then what shows the focus, or the whole of it where no part
/// is.
class PrefabTile extends StatelessWidget {
  const PrefabTile({
    super.key,
    required this.instance,
    required this.scope,
    this.onSelect,
    this.onMenu,
    this.onFocus,
    this.autofocus = false,
    this.boxStyle = BoxStyle.none,
  });

  final PrefabInstance instance;

  /// The variables its parts can read, by name.
  final Map<String, Object?> scope;

  /// What a press does; with neither this nor [onMenu] it is only looked
  /// at, and the focus passes it by.
  final VoidCallback? onSelect;
  final void Function(bool held)? onMenu;
  final void Function(bool focused)? onFocus;

  /// True for line art, which sits straight on the wallpaper with only a
  /// faint wash to show focus: what it is drawn from says so.
  bool get bare => switch (scope['source']) {
    {'bare': true} => true,
    _ => false,
  };
  final bool autofocus;

  /// The look it was given, which is that of whatever of it shows the
  /// focus.
  final BoxStyle boxStyle;

  Widget _framed(BuildContext context, bool focused, bool bare, Widget child) {
    final fill = styleFill(boxStyle);
    final outline = boxStyle.border;
    final shape = styleShape(boxStyle, 10);
    return AnimatedContainer(
      duration: FocusTile.duration,
      clipBehavior: Clip.antiAlias,
      // The border is drawn over the artwork so the tile does not change
      // size when focused.
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(
          color: focused
              ? Colors.white
              : outline == null
              ? Colors.transparent
              : Color(outline),
          width: outline == null ? 2 : boxStyle.borderWidth,
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
        boxShadow: styleShadow(boxStyle),
      ),
      child: child,
    );
  }

  /// One place of [layout]: a part, or a group of them.
  Widget? _place(
    BuildContext context,
    PrefabLayout layout,
    PrefabSlot slot,
    bool focused,
  ) {
    // Where everything takes only the room it needs, nothing is shared out.
    final sized = !layout.fit && (slot.flex != null || slot.aspect != null);
    Widget child;
    if (slot.group case final group?) {
      child = _arranged(context, group, focused, inner: true);
    } else {
      final part = instance.part(slot);
      if (part == null || part.hidden && !slot.keep) return null;
      child = WidgetTile.of(part.kind, part.options, shrink: !sized);
      if (part.options['frame'] == true) {
        child = _framed(context, focused, bare, child);
      }
      // Its room is kept either way, so hiding it does not change the size
      // of the rest.
      if (slot.keep) {
        child = Visibility.maintain(visible: !part.hidden, child: child);
      }
    }
    if (layout.fit) return child;
    if (slot.aspect case final aspect?) {
      child = AspectRatio(aspectRatio: aspect, child: child);
    }
    return slot.flex == null
        ? child
        : Expanded(flex: slot.flex!.round(), child: child);
  }

  Widget _arranged(
    BuildContext context,
    PrefabLayout layout,
    bool focused, {
    bool inner = false,
  }) {
    final flex = Flex(
      direction: layout.row ? Axis.horizontal : Axis.vertical,
      mainAxisSize: layout.fit || inner ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: inner
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: switch (layout.align) {
        'start' => CrossAxisAlignment.start,
        'end' => CrossAxisAlignment.end,
        'center' => CrossAxisAlignment.center,
        'stretch' => CrossAxisAlignment.stretch,
        // Stretching asks for all the room, which a fitted one has none of.
        _ when layout.row || layout.fit => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.stretch,
      },
      spacing: layout.gap,
      children: [
        for (final slot in layout.slots)
          ?_place(context, layout, slot, focused),
      ],
    );
    // Made as big as the box allows, once and at the top.
    return layout.fit && !inner ? FittedBox(child: flex) : flex;
  }

  @override
  Widget build(BuildContext context) {
    final layout = instance.layout;
    Widget content(bool focused) => TemplateScope(
      values: scope,
      child: _arranged(context, layout, focused),
    );
    if (onSelect == null && onMenu == null) return content(false);
    final framed = instance.parts.any((part) => part.options['frame'] == true);
    return FocusTile(
      autofocus: autofocus,
      onSelect: onSelect ?? () {},
      onMenu: onMenu,
      onFocus: onFocus,
      focusedScale: layout.row ? 1.04 : 1.08,
      builder: (context, focused) => TileFocus(
        focused: focused,
        // With no part to show the focus, the whole of it does.
        child: framed
            ? content(focused)
            : _framed(
                context,
                focused,
                true,
                Padding(
                  padding: EdgeInsets.all(boxStyle.padding ?? 8),
                  child: content(focused),
                ),
              ),
      ),
    );
  }
}
