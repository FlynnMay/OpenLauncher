import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home/tile_icons.dart';
import 'package:openlauncher/features/widgets/marquee.dart';

// The three a widget of the user's own is put together from. Each shows
// what its options say; an option that is text is a template, so
// `{{weather.temperature}}` in it is the temperature. How each looks is
// its `style`, over what the things around it hand down.

Color _colour(Object? css, [Color otherwise = Colors.white]) =>
    switch (BoxStyle.parseColor(css)) {
      null => otherwise,
      final argb => Color(argb),
    };

/// The variables in reach of the widgets below, by name: those of every
/// component around them that lets what is inside it read them. Looked in
/// before what is read by its id.
class TemplateScope extends InheritedWidget {
  const TemplateScope({super.key, required this.values, required super.child});

  /// By root name.
  final Map<String, Object?> values;

  /// The variables in reach of [context]: none where nothing set any.
  static Map<String, Object?> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TemplateScope>()?.values ??
      const {};

  @override
  bool updateShouldNotify(TemplateScope oldWidget) =>
      !mapEquals(values, oldWidget.values);
}

/// Says whether the tile the widgets below are part of has the focus, for
/// those that show it.
class TileFocus extends InheritedWidget {
  const TileFocus({super.key, required this.focused, required super.child});

  final bool focused;

  static bool? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileFocus>()?.focused;

  @override
  bool updateShouldNotify(TileFocus oldWidget) => focused != oldWidget.focused;
}

/// The look of a widget set up by [options], as it stands now: what it was
/// handed down, and its own over that.
Style _style(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> options,
) => readStyle(ref.watch, {
  ...StyleScope.of(context),
  ...styleFromJson(options['style']),
}, TemplateScope.of(context));

/// A template as it reads now; nothing for no template.
String _read(BuildContext context, WidgetRef ref, Object? template) {
  if (template is! String) return template == null ? '' : '$template';
  return valueText(
    readTemplate(ref.watch, template, TemplateScope.of(context)),
  );
}

/// Text made of values.
///
/// Options: `text` (a template), and for letters of a set size what is
/// done with text too long for the box, `overflow`: `fade` (the usual),
/// `ellipsis`, `clip`, `wrap` (onto as many lines as there is room for) or
/// `scroll` (moving along, at `speed` a second).
///
/// Look: `fontSize` (none to fill the box), `textAlign` (`left`, `center`,
/// `right`), `color`, `fontWeight` (`light`, `medium`, `bold`).
class TextWidget extends ConsumerWidget {
  const TextWidget({super.key, required this.options, this.shrink = false});

  final Map<String, Object?> options;

  /// True to take only the room one line needs, where it is one part of
  /// something laid out around it; otherwise it fills its box.
  final bool shrink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = _read(context, ref, options['text']);
    final look = _style(context, ref, options);
    final size = BoxStyle.number(look['fontSize'], 1);
    final (align, alignment) = switch (look['textAlign']) {
      'left' => (TextAlign.left, Alignment.centerLeft),
      'right' => (TextAlign.right, Alignment.centerRight),
      _ => (TextAlign.center, Alignment.center),
    };
    final style = TextStyle(
      // In a tile that shows the focus, plain text shows it too.
      color: _colour(
        look['color'],
        TileFocus.of(context) == false ? Colors.white60 : Colors.white,
      ),
      fontSize: size ?? 40,
      fontWeight: switch (look['fontWeight']) {
        'bold' => FontWeight.w600,
        'medium' => FontWeight.w500,
        _ => FontWeight.w300,
      },
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (shrink) {
      return Text(
        text,
        style: style,
        textAlign: align,
        maxLines: 1,
        overflow: options['overflow'] == 'fade'
            ? TextOverflow.fade
            : TextOverflow.ellipsis,
      );
    }
    if (text.isEmpty) return const SizedBox.expand();
    if (size == null) {
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
/// Options: `label` (a template), `icon` (a name in `tileIcons`). Look:
/// `color`, `fontSize`.
class ButtonWidget extends ConsumerWidget {
  const ButtonWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _read(context, ref, options['label']);
    final icon = tileIcons[options['icon']];
    final look = _style(context, ref, options);
    final colour = _colour(look['color']);
    final size = BoxStyle.number(look['fontSize'], 1) ?? 14;
    return Row(
      mainAxisAlignment: label.isEmpty
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      spacing: 10,
      children: [
        if (icon != null) Icon(icon, color: colour, size: size + 6),
        if (label.isNotEmpty)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colour, fontSize: size),
            ),
          ),
      ],
    );
  }
}

/// One of the launcher's small pictures, by its name; a value can say
/// which, as the weather says the sky's.
///
/// Options: `icon` (a template that reads as a name in `tileIcons`), `size`
/// (none to fill the box). Look: `color`.
class IconWidget extends ConsumerWidget {
  const IconWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = tileIcons[_read(context, ref, options['icon']).trim()];
    final size = options['size'];
    final colour = _colour(_style(context, ref, options)['color']);
    if (icon == null) {
      return SizedBox.square(dimension: size is num ? size.toDouble() : null);
    }
    return size is num
        ? Icon(icon, color: colour, size: size.toDouble())
        : FittedBox(child: Icon(icon, color: colour));
  }
}

/// What a folder looks like from outside, for whatever opens it.
///
/// Options: `folder` (a template that reads as the folder's id).
class FolderPicture extends ConsumerWidget {
  const FolderPicture({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FolderArt(folder: _read(context, ref, options['folder']).trim());
}

/// A picture from a web address or from a value, such as the cover of
/// what is playing.
///
/// Options: `source` (a template: a web address, a file, or a drawing as
/// SVG), `fit` (`cover`, or `contain` to show all of it), `pad` (room
/// left around it), `alt` (what to say when there is none). Look: `radius`
/// (of its corners).
class PictureWidget extends ConsumerWidget {
  const PictureWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = _read(context, ref, options['source']).trim();
    final look = BoxStyle.of(_style(context, ref, options));
    final pad = double.tryParse(_read(context, ref, options['pad'])) ?? 0;
    final alt = _read(context, ref, options['alt']);
    final fit = _read(context, ref, options['fit']) == 'contain'
        ? BoxFit.contain
        : BoxFit.cover;
    // With no picture: what it is called, or the mark of an empty one.
    final none = Center(
      child: alt.isEmpty
          ? const Icon(Icons.image_outlined, color: Colors.white24)
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                alt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
    );
    if (source.isEmpty) return none;
    return ClipRRect(
      borderRadius: styleShape(look, 6),
      child: Padding(
        padding: EdgeInsets.all(pad),
        // Line art comes as the drawing itself, not as where it is kept.
        child: source.startsWith('<')
            ? SvgPicture.string(source, fit: BoxFit.contain)
            : Image(
                image: source.startsWith(RegExp('https?://'))
                    ? NetworkImage(source)
                    : pictureAt(source),
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => none,
              ),
      ),
    );
  }
}

/// How far a number is between two others, as a bar or a ring.
///
/// Options: `value` (a template that reads as a number), `min` (0), `max`
/// (100), `shape` (`bar` or `ring`). Look: `color`.
class MeterWidget extends ConsumerWidget {
  const MeterWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double number(Object? option, double otherwise) => switch (option) {
      final num number => number.toDouble(),
      _ => otherwise,
    };
    final value = double.tryParse(_read(context, ref, options['value']).trim());
    final min = number(options['min'], 0), max = number(options['max'], 100);
    final part = value == null || max <= min
        ? 0.0
        : ((value - min) / (max - min)).clamp(0.0, 1.0);
    final colour = _colour(_style(context, ref, options)['color']);
    return SizedBox.expand(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: part),
        duration: const Duration(milliseconds: 300),
        builder: (context, part, _) => CustomPaint(
          painter: _MeterPainter(
            part: part,
            ring: options['shape'] == 'ring',
            colour: colour,
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
