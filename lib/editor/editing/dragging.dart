import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// Something being dragged: a placed component or a new one from the
/// catalogue.
class Dragged {
  const Dragged({
    required this.item,
    required this.label,
    required this.picture,
    this.opens,
    this.placed = false,
  }) : template = null;

  /// A new pane made from [template]. It can only go to a free screen edge,
  /// where it docks.
  const Dragged.docking({
    required this.label,
    required this.picture,
    required Prefab this.template,
  }) : item = const Node(id: 'docking'),
       opens = null,
       placed = false;

  final Node item;

  /// The new docked pane that [item] opens, if any.
  final Node? opens;

  /// Whether [item] is already in the layout.
  final bool placed;

  /// What a new pane going to an edge is made from; [item] is then a
  /// placeholder.
  final Prefab? template;

  bool get docking => template != null;

  final String label;
  final Widget picture;
}

/// Makes its child draggable: at once with a mouse, after a hold with touch
/// so swipes still scroll.
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
    // Held by its centre, slightly above the finger.
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
            // Over the whole page, not only the launcher's own screen.
            rootOverlay: true,
            feedback: feedback,
            childWhenDragging: resting,
            child: child,
          )
        : Draggable<Dragged>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            // Over the whole page, not only the launcher's own screen.
            rootOverlay: true,
            feedback: feedback,
            childWhenDragging: resting,
            child: child,
          );
  }
}

/// The chip that follows the pointer.
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

/// An icon for things with no picture.
class SymbolArt extends StatelessWidget {
  const SymbolArt(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => FittedBox(
    child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon)),
  );
}
