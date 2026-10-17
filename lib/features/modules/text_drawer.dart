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
    if (shrink) {
      return Text(
        text,
        style: style,
        textAlign: align,
        maxLines: 1,
        overflow: values['overflow'] == 'fade'
            ? TextOverflow.fade
            : TextOverflow.ellipsis,
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
    final speed = values['speed'];
    return SizedBox.expand(
      child: switch (values['overflow']) {
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
              // As many whole lines as fit.
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
