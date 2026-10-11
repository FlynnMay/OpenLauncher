import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/home/tile_icons.dart';
import 'package:openlauncher/features/widgets/marquee.dart';

// The three a widget of the user's own is put together from. Each shows
// what its options say; an option that is text is a template, so
// `{{weather.temperature}}` in it is the temperature.

Color _colour(Object? css, [Color otherwise = Colors.white]) =>
    switch (BoxStyle.parseColor(css)) {
      null => otherwise,
      final argb => Color(argb),
    };

/// A template as it reads now; nothing for no template.
String _read(WidgetRef ref, Object? template) => template is String
    ? ref.watch(templateProvider(template))
    : switch (template) {
        null => '',
        _ => '$template',
      };

/// Text made of values.
///
/// Options: `text` (a template), `size` (of the letters; none to fill the
/// box), `align` (`left`, `center`, `right`), `colour`, `bold`, and for
/// letters of a set size what is done with text too long for the box,
/// `overflow`: `fade` (the usual), `ellipsis`, `clip`, `wrap` (onto as many
/// lines as there is room for) or `scroll` (moving along, at `speed` a
/// second).
class TextWidget extends ConsumerWidget {
  const TextWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = _read(ref, options['text']);
    final size = options['size'];
    final (align, alignment) = switch (options['align']) {
      'left' => (TextAlign.left, Alignment.centerLeft),
      'right' => (TextAlign.right, Alignment.centerRight),
      _ => (TextAlign.center, Alignment.center),
    };
    final style = TextStyle(
      color: _colour(options['colour']),
      fontSize: size is num ? size.toDouble() : 40,
      fontWeight: options['bold'] == true ? FontWeight.w600 : FontWeight.w300,
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (text.isEmpty) return const SizedBox.expand();
    if (size is! num) {
      // Made to fit, so never too long.
      return SizedBox.expand(
        child: FittedBox(
          alignment: alignment,
          child: Text(text, style: style, textAlign: align),
        ),
      );
    }
    final speed = options['speed'];
    return SizedBox.expand(
      child: switch (options['overflow']) {
        'scroll' => Marquee(
          text: text.replaceAll('\n', ' '),
          style: style,
          alignment: alignment,
          speed: speed is num ? speed.toDouble() : 40,
        ),
        'wrap' => LayoutBuilder(
          builder: (context, box) => Align(
            alignment: alignment,
            child: Text(
              text,
              style: style,
              textAlign: align,
              // As many lines as there is room for, and no part of one.
              maxLines: (box.maxHeight / (style.fontSize! * style.height!))
                  .floor()
                  .clamp(1, 100),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        final overflow => Align(
          alignment: alignment,
          child: Text(
            text,
            style: style,
            textAlign: align,
            maxLines: 1,
            softWrap: false,
            overflow: switch (overflow) {
              'ellipsis' => TextOverflow.ellipsis,
              'clip' => TextOverflow.clip,
              _ => TextOverflow.fade,
            },
          ),
        ),
      },
    );
  }
}

/// Something to press: a small picture and a line of text, either of which
/// may be left out. What pressing it does is in its item's triggers, and
/// how it shows the focus is its tile's business.
///
/// Options: `label` (a template), `icon` (a name in `tileIcons`), `colour`.
class ButtonWidget extends ConsumerWidget {
  const ButtonWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _read(ref, options['label']);
    final icon = tileIcons[options['icon']];
    final colour = _colour(options['colour']);
    return Row(
      mainAxisAlignment: label.isEmpty
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      spacing: 10,
      children: [
        if (icon != null) Icon(icon, color: colour, size: 20),
        if (label.isNotEmpty)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colour, fontSize: 14),
            ),
          ),
      ],
    );
  }
}

/// A picture from a web address or from a value, such as the cover of
/// what is playing.
///
/// Options: `source` (a template), `fit` (`cover`, or `contain` to show
/// all of it), `round` (its corners).
class PictureWidget extends ConsumerWidget {
  const PictureWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = _read(ref, options['source']).trim();
    final round = options['round'];
    const none = Center(
      child: Icon(Icons.image_outlined, color: Colors.white24),
    );
    if (source.isEmpty) return none;
    return ClipRRect(
      borderRadius: BorderRadius.circular(round is num ? round.toDouble() : 6),
      child: Image(
        image: source.startsWith(RegExp('https?://'))
            ? NetworkImage(source)
            : pictureAt(source),
        fit: options['fit'] == 'contain' ? BoxFit.contain : BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => none,
      ),
    );
  }
}

/// How far a number is between two others, as a bar or a ring.
///
/// Options: `value` (a template that reads as a number), `min` (0), `max`
/// (100), `shape` (`bar` or `ring`), `colour`.
class MeterWidget extends ConsumerWidget {
  const MeterWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double number(Object? option, double otherwise) => switch (option) {
      final num number => number.toDouble(),
      _ => otherwise,
    };
    final value = double.tryParse(_read(ref, options['value']).trim());
    final min = number(options['min'], 0), max = number(options['max'], 100);
    final part = value == null || max <= min
        ? 0.0
        : ((value - min) / (max - min)).clamp(0.0, 1.0);
    return SizedBox.expand(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: part),
        duration: const Duration(milliseconds: 300),
        builder: (context, part, _) => CustomPaint(
          painter: _MeterPainter(
            part: part,
            ring: options['shape'] == 'ring',
            colour: _colour(options['colour']),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({
    required this.part,
    required this.ring,
    required this.colour,
  });

  final double part;
  final bool ring;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = colour.withValues(alpha: colour.a * 0.2);
    final fill = Paint()..color = colour;
    if (!ring) {
      final height = math.min(size.height, 10.0);
      final bar = Rect.fromLTWH(
        0,
        (size.height - height) / 2,
        size.width,
        height,
      );
      final radius = Radius.circular(height / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, radius), track);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * part, height),
          radius,
        ),
        fill,
      );
      return;
    }
    final width = math.max(3.0, size.shortestSide * 0.1);
    final circle = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - width) / 2,
    );
    for (final paint in [track, fill]) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
    }
    canvas.drawArc(circle, 0, 2 * math.pi, false, track);
    // From the top, clockwise.
    canvas.drawArc(circle, -math.pi / 2, 2 * math.pi * part, false, fill);
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.part != part || old.ring != ring || old.colour != colour;
}
