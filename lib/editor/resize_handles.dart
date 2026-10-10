import 'package:flutter/material.dart';

/// A place a box can be taken hold of to change its size: a side or a
/// corner.
enum ResizeHandle {
  topLeft(-1, -1),
  top(0, -1),
  topRight(1, -1),
  left(-1, 0),
  right(1, 0),
  bottomLeft(-1, 1),
  bottom(0, 1),
  bottomRight(1, 1);

  const ResizeHandle(this.dx, this.dy);

  /// Which way it pulls: -1 for the left or top edge, 1 for the right or
  /// bottom, 0 for neither.
  final int dx, dy;

  MouseCursor get cursor => switch (this) {
    left || right => SystemMouseCursors.resizeLeftRight,
    top || bottom => SystemMouseCursors.resizeUpDown,
    topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
  };
}

/// Handles around [rect], to be laid in a [Stack] over whatever the box is.
/// It only reports: how far a handle has been dragged since it was taken
/// hold of, and when it is let go. What that does to the box is the
/// caller's, who moves [rect] to show it.
class ResizeHandles extends StatefulWidget {
  const ResizeHandles({
    super.key,
    required this.rect,
    required this.onDragged,
    required this.onDone,
    this.handles = const {...ResizeHandle.values},
    this.colour = Colors.lightBlueAccent,
    this.size = 9,
    this.reach = 22,
  });

  final Rect rect;
  final Set<ResizeHandle> handles;
  final void Function(ResizeHandle handle, Offset moved) onDragged;

  /// Called when a handle is let go; [kept] is false if the drag was
  /// broken off and nothing should come of it.
  final void Function({required bool kept}) onDone;
  final Color colour;

  /// How big a handle looks, and how big the area that takes hold of it is.
  final double size, reach;

  @override
  State<ResizeHandles> createState() => _ResizeHandlesState();
}

class _ResizeHandlesState extends State<ResizeHandles> {
  Offset _moved = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final reach = widget.reach;
    return Positioned.fromRect(
      rect: widget.rect.inflate(reach / 2),
      child: Stack(
        children: [
          // The outline of the box itself, which cannot be taken hold of.
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.all(reach / 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.colour, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          for (final handle in widget.handles)
            Align(
              key: ValueKey(handle),
              alignment: Alignment(handle.dx * 1.0, handle.dy * 1.0),
              child: MouseRegion(
                cursor: handle.cursor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => _moved = Offset.zero,
                  onPanUpdate: (details) {
                    _moved += details.delta;
                    widget.onDragged(handle, _moved);
                  },
                  onPanEnd: (_) => widget.onDone(kept: true),
                  onPanCancel: () => widget.onDone(kept: false),
                  child: SizedBox.square(
                    dimension: reach,
                    child: Center(
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: widget.colour, width: 2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
