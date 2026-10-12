import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/styled_box.dart';

/// Where a scroll bar's track and thumb go in a box of [size]. Null when
/// there is nothing to scroll. [progress] fills from the start instead of
/// moving a thumb; [both] leaves the corner to the other axis's bar.
({Rect track, Rect thumb, Rect travel})? barRects(
  Size size,
  ScrollMetrics metrics,
  ScrollbarStyle look, {
  bool progress = false,
  bool both = false,
}) {
  if (!metrics.hasContentDimensions || !metrics.hasPixels) return null;
  final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
  if (extent <= 0) return null;
  final vertical = metrics.axis == Axis.vertical;
  final corner = both ? look.size + look.margin : 0.0;
  final room =
      (vertical ? size.height : size.width) - 2 * look.endMargin - corner;
  final long = room * look.length;
  final inner = long - 2 * look.inset;
  if (inner <= 0) return null;
  final from = look.endMargin + (look.start ? corner : 0) + (room - long) / 2;
  final at = look.start
      ? look.margin
      : (vertical ? size.width : size.height) - look.margin - look.size;
  Rect rect(double start, double length, double inset) => vertical
      ? Rect.fromLTWH(at + inset, from + start, look.size - 2 * inset, length)
      : Rect.fromLTWH(from + start, at + inset, length, look.size - 2 * inset);

  final done = ((metrics.pixels - metrics.minScrollExtent) / extent).clamp(
    0.0,
    1.0,
  );
  final reversed = axisDirectionIsReversed(metrics.axisDirection);
  final length = progress
      ? inner * done
      : (inner *
                metrics.viewportDimension /
                (extent + metrics.viewportDimension))
            .clamp(min(look.minLength, inner), inner)
            .toDouble();
  final before = progress ? 0.0 : (inner - length) * done;
  return (
    track: rect(0, long, 0),
    thumb: rect(
      look.inset + (reversed ? inner - length - before : before),
      length,
      look.inset,
    ),
    travel: rect(look.inset, inner, look.inset),
  );
}

/// Draws [pane]'s scroll bars over [child], which holds its scroll views.
class PaneScrollbars extends StatefulWidget {
  const PaneScrollbars({
    super.key,
    required this.pane,
    required this.style,
    required this.child,
  });

  final Component pane;

  /// The pane's style, templates read.
  final Style style;
  final Widget child;

  /// [child] under [pane]'s scroll bars, if it has any.
  static Widget over(Component pane, Style style, Widget child) =>
      pane.scrollbar == null
      ? child
      : PaneScrollbars(pane: pane, style: style, child: child);

  /// How long one that hides stays after the last movement, fade included.
  static const linger = Duration(milliseconds: 1200);

  @override
  State<PaneScrollbars> createState() => _PaneScrollbarsState();
}

class _PaneScrollbarsState extends State<PaneScrollbars>
    with SingleTickerProviderStateMixin {
  final _down = ValueNotifier<ScrollMetrics?>(null);
  final _across = ValueNotifier<ScrollMetrics?>(null);
  late final _shown = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    _flash();
  }

  @override
  void didUpdateWidget(PaneScrollbars old) {
    super.didUpdateWidget(old);
    final pane = widget.pane;
    if (!pane.scrollsDown) _down.value = null;
    if (!pane.scrollsAcross) _across.value = null;
    // A change to its look shows it.
    if (pane.scrollbarHides != old.pane.scrollbarHides ||
        !mapEquals(widget.style, old.style)) {
      _flash();
    }
  }

  /// Shows it; one that hides then fades after a while.
  void _flash() {
    _shown.value = 1;
    if (widget.pane.scrollbarHides) {
      _shown.animateBack(
        0,
        duration: PaneScrollbars.linger,
        curve: const Interval(0.75, 1),
      );
    }
  }

  bool _heard(Notification notification) {
    final ScrollMetrics metrics;
    final int depth;
    switch (notification) {
      case ScrollMetricsNotification():
        (metrics, depth) = (notification.metrics, notification.depth);
      case ScrollUpdateNotification():
        (metrics, depth) = (notification.metrics, notification.depth);
      default:
        return false;
    }
    // Its own scroll views only: the one across is inside the one down.
    final pane = widget.pane;
    if (metrics.axis == Axis.vertical) {
      if (!pane.scrollsDown || depth != 0) return false;
      _down.value = metrics;
    } else {
      if (!pane.scrollsAcross || depth != (pane.scrollsDown ? 1 : 0)) {
        return false;
      }
      _across.value = metrics;
    }
    if (notification is ScrollUpdateNotification) _flash();
    return false;
  }

  @override
  void dispose() {
    _shown.dispose();
    _down.dispose();
    _across.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = ScrollbarStyle.of(widget.style);
    return NotificationListener<Notification>(
      onNotification: _heard,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _shown.drive(Tween(begin: 0, end: look.opacity)),
                child: CustomPaint(
                  painter: _BarPainter(
                    look,
                    _down,
                    _across,
                    progress: widget.pane.scrollbar == 'progress',
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

class _BarPainter extends CustomPainter {
  _BarPainter(this.look, this.down, this.across, {required this.progress})
    : super(repaint: Listenable.merge([down, across]));

  final ScrollbarStyle look;
  final ValueListenable<ScrollMetrics?> down, across;
  final bool progress;

  static const _thumb = Color(0x99FFFFFF), _track = Color(0x33FFFFFF);

  /// Paints [box]'s fill and border in [rect]; a gradient is spread over
  /// [spread].
  static void _box(
    Canvas canvas,
    Rect rect,
    BoxStyle box, {
    Color? fallback,
    Rect? spread,
  }) {
    if (rect.isEmpty) return;
    final shape = styleShape(box, rect.shortestSide / 2).toRRect(rect);
    final fill = styleFill(box);
    final color = fill.color ?? fallback;
    if (fill.gradient case final gradient?) {
      canvas.drawRRect(
        shape,
        Paint()..shader = gradient.createShader(spread ?? rect),
      );
    } else if (color != null) {
      canvas.drawRRect(shape, Paint()..color = color);
    }
    if (box.border case final border? when box.borderWidth > 0) {
      canvas.drawRRect(
        shape.deflate(box.borderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = box.borderWidth
          ..color = Color(border),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final both = [down.value, across.value].nonNulls.toList();
    for (final metrics in both) {
      final rects = barRects(
        size,
        metrics,
        look,
        progress: progress,
        both: both.length > 1,
      );
      if (rects == null) continue;
      // A progress bar with no track would show nothing at the start.
      _box(canvas, rects.track, look.track, fallback: progress ? _track : null);
      // A progress bar's gradient is uncovered as it fills.
      _box(
        canvas,
        rects.thumb,
        look.thumb,
        fallback: _thumb,
        spread: progress ? rects.travel : null,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}
