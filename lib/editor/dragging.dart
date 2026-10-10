import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// Something being dragged: an item that is already on the TV, or one from
/// the catalogue that will be once it is dropped.
class Dragged {
  const Dragged({
    required this.item,
    required this.label,
    required this.picture,
    this.panel,
    this.placed = false,
  });

  final LayoutItem item;

  /// A new popup that comes with [item], when it is a new folder.
  final Panel? panel;

  /// True when [item] is somewhere in the layout already.
  final bool placed;

  /// What follows the pointer while it is dragged.
  final String label;
  final Widget picture;
}

/// Lets what is in it be picked up: at once with a mouse, after a hold with
/// a finger, so that a swipe still scrolls.
class DragHandle extends StatelessWidget {
  const DragHandle({super.key, required this.data, required this.child});

  final Dragged data;
  final Widget child;

  static const holdTime = Duration(milliseconds: 280);

  static bool get _byFinger =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    // Held by its middle, a little above a finger so it is not hidden.
    final feedback = FractionalTranslation(
      translation: Offset(-0.5, _byFinger ? -1.1 : -0.5),
      child: _Chip(data),
    );
    final resting = Opacity(opacity: 0.35, child: child);
    return _byFinger
        ? LongPressDraggable<Dragged>(
            data: data,
            delay: holdTime,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: resting,
            child: child,
          )
        : Draggable<Dragged>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: resting,
            child: child,
          );
  }
}

/// The small copy of a dragged thing that follows the pointer. Where it
/// will land, and how big, is shown on the screen replica itself.
class _Chip extends StatelessWidget {
  const _Chip(this.data);

  final Dragged data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 112,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: data.picture),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture for things that have none of their own: a pane, a widget.
class SymbolArt extends StatelessWidget {
  const SymbolArt(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => FittedBox(
    child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon)),
  );
}
