import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';
import 'package:openlauncher/features/modules/visual_look.dart';

/// A picture from a web address or from a value, such as the cover of
/// what is playing.
///
/// Values: `source` (a template: a web address, a file, or a drawing as
/// SVG), `fit` (`cover`, or `contain` to show all of it), `pad` (room
/// left around it), `alt` (what to say when there is none), `badge` (text
/// in a pill over its lower right). Look: `radius` (of its corners).
class PictureVisual extends ConsumerWidget {
  const PictureVisual({super.key, required this.values});

  /// Its module's values, with its style under `style`.
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = visualText(context, ref, values['source']).trim();
    final look = BoxStyle.of(visualStyle(context, ref, values));
    final pad = double.tryParse(visualText(context, ref, values['pad'])) ?? 0;
    final alt = visualText(context, ref, values['alt']);
    final fit = visualText(context, ref, values['fit']) == 'contain'
        ? BoxFit.contain
        : BoxFit.cover;
    // No picture: the alt text, or a placeholder.
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
    final badge = visualText(context, ref, values['badge']).trim();
    final picture = source.startsWith('<') || !kIsWeb && source.endsWith('.svg')
        ? svgPicture(source)
        : Image(
            image: source.startsWith(RegExp('https?://'))
                ? NetworkImage(source)
                : pictureAt(source),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => none,
          );
    return ClipRRect(
      borderRadius: styleShape(look, 6),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: badge.isEmpty
            ? picture
            : Stack(
                fit: StackFit.expand,
                children: [picture, svgPicture(badgeSvg(badge))],
              ),
      ),
    );
  }
}
