import 'package:flutter/material.dart';

/// Where both edges on one axis are anchored, as fractions of the parent.
typedef AxisAnchors = (double, double);

/// The presets on each axis: the start, the middle, the end, or stretched
/// from start to end.
const axisPresets = <AxisAnchors>[(0, 0), (0.5, 0.5), (1, 1), (0, 1)];

const _across = ['Left', 'Centre', 'Right', 'Stretch across'];
const _down = ['Top', 'Middle', 'Bottom', 'Stretch down'];

/// A grid of anchor presets, Unity style: rows from top to stretched down,
/// columns from left to stretched across. The one matching [x] and [y] is
/// marked.
class AnchorPresets extends StatelessWidget {
  const AnchorPresets({
    super.key,
    required this.x,
    required this.y,
    required this.onPicked,
  });

  final AxisAnchors x, y;
  final void Function(AxisAnchors x, AxisAnchors y) onPicked;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 2,
    children: [
      for (final (row, down) in axisPresets.indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final (column, across) in axisPresets.indexed)
              _Preset(
                label: '${_down[row]}, ${_across[column]}'.toLowerCase(),
                x: across,
                y: down,
                picked: across == x && down == y,
                onTap: () => onPicked(across, down),
              ),
          ],
        ),
    ],
  );
}

class _Preset extends StatelessWidget {
  const _Preset({
    required this.label,
    required this.x,
    required this.y,
    required this.picked,
    required this.onTap,
  });

  final String label;
  final AxisAnchors x, y;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label[0].toUpperCase() + label.substring(1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: picked ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: CustomPaint(
            painter: _PresetPainter(
              x: x,
              y: y,
              frame: scheme.outline,
              box: scheme.onSurfaceVariant,
              anchor: scheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

/// The parent as a square, the node in it, and its anchors as ticks.
class _PresetPainter extends CustomPainter {
  const _PresetPainter({
    required this.x,
    required this.y,
    required this.frame,
    required this.box,
    required this.anchor,
  });

  final AxisAnchors x, y;
  final Color frame, box, anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final parent = (Offset.zero & size).deflate(7);
    canvas.drawRect(
      parent,
      Paint()
        ..color = frame
        ..style = PaintingStyle.stroke,
    );
    // A stretched axis fills, less a margin; a pinned one is a small box
    // at its anchor.
    (double, double) span(AxisAnchors at, double from, double length) =>
        at.$1 != at.$2
        ? (from + 3, from + length - 3)
        : switch (from + at.$1 * length) {
            final mid => (
              (mid - 3).clamp(from + 2, from + length - 8),
              (mid + 3).clamp(from + 8, from + length - 2),
            ),
          };
    final (left, right) = span(x, parent.left, parent.width);
    final (top, bottom) = span(y, parent.top, parent.height);
    canvas.drawRect(
      Rect.fromLTRB(left, top, right, bottom),
      Paint()..color = box,
    );
    final ticks = Paint()
      ..color = anchor
      ..strokeWidth = 1.5;
    for (final ax in {x.$1, x.$2}) {
      for (final ay in {y.$1, y.$2}) {
        final at = Offset(
          parent.left + ax * parent.width,
          parent.top + ay * parent.height,
        );
        canvas.drawCircle(at, 1.6, ticks);
      }
    }
  }

  @override
  bool shouldRepaint(_PresetPainter old) =>
      old.x != x ||
      old.y != y ||
      old.frame != frame ||
      old.box != box ||
      old.anchor != anchor;
}
