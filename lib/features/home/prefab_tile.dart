import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/features/widgets/widget_tile.dart';

/// An instance of a prefab as a tile: its parts, arranged as its layout
/// says, reading [source] for whatever they are written against. The part
/// marked `frame` is the entity proper, which carries the background and
/// shows the focus.
class PrefabTile extends StatelessWidget {
  const PrefabTile({
    super.key,
    required this.instance,
    required this.source,
    required this.onSelect,
    this.onMenu,
    this.onFocus,
    this.bare = false,
    this.autofocus = false,
    this.boxStyle = BoxStyle.none,
    this.custom = const {},
  });

  final PrefabInstance instance;
  final Map<String, Object?> source;
  final VoidCallback onSelect;
  final void Function(bool held)? onMenu;
  final void Function(bool focused)? onFocus;

  /// True for line art, which sits straight on the wallpaper with only a
  /// faint wash to show focus.
  final bool bare;
  final bool autofocus;

  /// The fill and outline the user gave it, if any.
  final BoxStyle boxStyle;

  /// What draws a part of a kind that is not a widget's, by that kind:
  /// what only the launcher knows how to draw, such as a folder's face.
  final Map<String, Widget> custom;

  Widget _framed(BuildContext context, bool focused, Widget child) {
    final fill = styleFill(boxStyle);
    final outline = boxStyle.border;
    return AnimatedContainer(
      duration: FocusTile.duration,
      clipBehavior: Clip.antiAlias,
      // The border is drawn over the artwork so the entity does not change
      // size when focused.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused
              ? Colors.white
              : outline == null
              ? Colors.transparent
              : Color(outline),
          width: 2,
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = instance.layout;
    return FocusTile(
      autofocus: autofocus,
      onSelect: onSelect,
      onMenu: onMenu,
      onFocus: onFocus,
      focusedScale: layout.row ? 1.04 : 1.08,
      builder: (context, focused) => TileFocus(
        focused: focused,
        child: TemplateScope(
          values: {'source': source},
          child: Flex(
            direction: layout.row ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: layout.row
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            spacing: layout.gap,
            children: [
              for (final part in instance.parts)
                if (!part.hidden || part.slot.keep)
                  () {
                    final slot = part.slot;
                    final sized = slot.flex != null || slot.aspect != null;
                    Widget child =
                        custom[part.kind] ??
                        WidgetTile.of(part.kind, part.options, shrink: !sized);
                    if (part.options['frame'] == true) {
                      child = _framed(context, focused, child);
                    }
                    // Its room is kept either way, so hiding it does not
                    // change the size of the rest.
                    if (slot.keep) {
                      child = Visibility.maintain(
                        visible: !part.hidden,
                        child: child,
                      );
                    }
                    if (slot.aspect case final aspect?) {
                      child = AspectRatio(aspectRatio: aspect, child: child);
                    }
                    return slot.flex == null
                        ? child
                        : Expanded(flex: slot.flex!.round(), child: child);
                  }(),
            ],
          ),
        ),
      ),
    );
  }
}
