import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/components/marquee.dart';
import 'package:openlauncher/features/modules/focus_drawer.dart';
import 'package:openlauncher/features/modules/visual_look.dart';

/// Text made of values.
///
/// Values: `text` (a template), and for letters of a set size what is
/// done with text too long for the box, `overflow`: `fade` (the default),
/// `ellipsis`, `clip`, `wrap` (onto as many lines as there is room for) or
/// `scroll` (moving along, at `speed` a second).
///
/// Look: `fontSize` (none to fill the box), `textAlign` (`left`, `center`,
/// `right`), `color`, `fontWeight` (`light`, `medium`, `bold`).
class TextVisual extends ConsumerWidget {
  const TextVisual({super.key, required this.values, this.shrink = false});

  /// Its module's values, with its style under `style`.
  final Map<String, Object?> values;

  /// Take one line's natural size instead of filling the box.
  final bool shrink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = visualText(context, ref, values['text']);
    final look = visualStyle(context, ref, values);
    final size = BoxStyle.number(look['fontSize'], 1);
    final (align, alignment) = switch (look['textAlign']) {
      'left' => (TextAlign.left, Alignment.centerLeft),
      'right' => (TextAlign.right, Alignment.centerRight),
      _ => (TextAlign.center, Alignment.center),
    };
    final style = TextStyle(
      // Dimmed when its tile is unfocused.
      color: cssColour(
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
    final overflow = values['overflow'] ?? 'fade';
    final speed = values['speed'];
    if (shrink) {
      return _atNaturalSize(
        text,
        style,
        align,
        alignment,
        overflow,
        speed is num ? speed.toDouble() : 40,
      );
    }
    if (text.isEmpty) return const SizedBox.expand();
    if (size == null) {
      // Scaled to fit, so never too long.
      return SizedBox.expand(
        child: FittedBox(
          alignment: alignment,
          child: Text(text, style: style, textAlign: align),
        ),
      );
    }
    return SizedBox.expand(
      child: switch (overflow) {
        'scroll' => Marquee(
          text: text.replaceAll('\n', ' '),
          style: style,
          alignment: alignment,
          speed: speed is num ? speed.toDouble() : 40,
        ),
        'wrap' => LayoutBuilder(
          builder: (context, box) => Align(
            alignment: alignment,
            child: _wrapped(text, style, align, _linesIn(box, style)),
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

  /// [text] over as many lines as it needs, or as there are room for. An
  /// ellipsis with no limit on the lines would keep it to one.
  static Widget _wrapped(
    String text,
    TextStyle style,
    TextAlign align,
    int? lines,
  ) => Text(
    text,
    style: style,
    textAlign: align,
    maxLines: lines,
    overflow: lines == null ? TextOverflow.clip : TextOverflow.ellipsis,
  );

  /// As many whole lines as [box] has room for; all of them if its height has
  /// no limit.
  static int? _linesIn(BoxConstraints box, TextStyle style) {
    if (!box.hasBoundedHeight) return null;
    return (box.maxHeight / (style.fontSize! * style.height!)).floor().clamp(
      1,
      100,
    );
  }

  /// One line's natural size, or as much of it as the room around allows,
  /// with what is done about text too long for that room.
  Widget _atNaturalSize(
    String text,
    TextStyle style,
    TextAlign align,
    Alignment alignment,
    Object? overflow,
    double speed,
  ) => LayoutBuilder(
    builder: (context, box) {
      Widget oneLine(TextOverflow how) => Text(
        text,
        style: style,
        textAlign: align,
        maxLines: 1,
        softWrap: false,
        overflow: how,
      );
      return switch (overflow) {
        'ellipsis' => oneLine(TextOverflow.ellipsis),
        'clip' => oneLine(TextOverflow.clip),
        // Onto as many lines as it needs, within the height there is.
        'wrap' => _wrapped(text, style, align, _linesIn(box, style)),
        // It can only move along in a width it knows.
        'scroll' when box.hasBoundedWidth => SizedBox(
          height: style.fontSize! * style.height!,
          child: Marquee(
            text: text.replaceAll('\n', ' '),
            style: style,
            alignment: alignment,
            speed: speed,
          ),
        ),
        _ => oneLine(TextOverflow.fade),
      };
    },
  );
}
