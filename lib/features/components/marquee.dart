import 'package:flutter/material.dart';

/// Text that scrolls in a loop when too long for its box; otherwise it sits
/// at [alignment].
class Marquee extends StatefulWidget {
  const Marquee({
    super.key,
    required this.text,
    required this.style,
    this.alignment = Alignment.center,
    this.speed = 40,
  });

  final String text;
  final TextStyle style;
  final Alignment alignment;

  /// Pixels per second.
  final double speed;

  /// Gap between the end of the text and its start.
  static const gap = 48.0;

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final _round = AnimationController(vsync: this);

  /// Duration of one loop; zero while the text fits.
  Duration _takes = Duration.zero;

  /// Starts or stops the loop. Deferred because it is found out during build.
  void _run(Duration takes) {
    if (takes == _takes) return;
    _takes = takes;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || takes != _takes) return;
      if (takes == Duration.zero) {
        _round
          ..stop()
          ..value = 0;
      } else {
        _round
          ..duration = takes
          ..repeat();
      }
    });
  }

  @override
  void dispose() {
    _round.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final line = Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      );
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width <= box.maxWidth || widget.speed <= 0) {
        _run(Duration.zero);
        return Align(alignment: widget.alignment, child: line);
      }
      final distance = width + Marquee.gap;
      _run(Duration(milliseconds: (distance / widget.speed * 1000).round()));
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment(-1, widget.alignment.y),
          maxWidth: double.infinity,
          child: AnimatedBuilder(
            animation: _round,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_round.value * distance, 0),
              child: child,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                line,
                const SizedBox(width: Marquee.gap),
                line,
              ],
            ),
          ),
        ),
      );
    },
  );
}
