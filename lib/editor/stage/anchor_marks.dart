import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// The selected node's anchors in its [parent], Unity style: the parent's
/// outline, and a small triangle at each anchor pointing out of the box the
/// anchors make.
class AnchorMarks extends CustomPainter {
  const AnchorMarks({required this.parent, required this.transform});

  final Rect parent;
  final NodeTransform transform;

  static const _colour = Color(0xffffffff), _shade = Color(0x99000000);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      parent,
      Paint()
        ..color = const Color(0x55ffffff)
        ..style = PaintingStyle.stroke,
    );
    Offset at(double x, double y) =>
        Offset(parent.left + x * parent.width, parent.top + y * parent.height);
    final t = transform;
    // Each corner of the anchors' box, and which way is out of it.
    for (final (x, y, dx, dy) in [
      (t.minX, t.minY, -1.0, -1.0),
      (t.maxX, t.minY, 1.0, -1.0),
      (t.minX, t.maxY, -1.0, 1.0),
      (t.maxX, t.maxY, 1.0, 1.0),
    ]) {
      final tip = at(x, y);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + dx * 10, tip.dy + dy * 4)
        ..lineTo(tip.dx + dx * 4, tip.dy + dy * 10)
        ..close();
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = _shade
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..drawPath(path, Paint()..color = _colour);
    }
  }

  @override
  bool shouldRepaint(AnchorMarks old) =>
      old.parent != parent || old.transform != transform;
}
