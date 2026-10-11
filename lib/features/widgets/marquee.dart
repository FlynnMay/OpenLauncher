import 'package:flutter/material.dart';

/// A line of text that, when it is too long for its box, moves along
/// through it and comes round again; one that fits stays where [alignment]
/// puts it.
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

  /// How far it moves in a second.
  final double speed;

  /// The room between the end of the text and its start coming round.
  static const gap = 48.0;

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final _round = AnimationController(vsync: this);

  /// How long one round takes now; zero while the text fits.
  Duration _takes = Duration.zero;

  /// Has the text go round in [takes], or stand still for zero. Not done
  /// during a build, which is when it is found out.
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
