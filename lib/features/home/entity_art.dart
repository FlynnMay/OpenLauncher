import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/picture.dart';

/// The picture of an entity: its artwork, line art, or failing both its name.
class EntityArt extends StatelessWidget {
  const EntityArt({super.key, required this.entity, this.padding = 14});

  final Entity entity;

  /// Space left around a square icon.
  final double padding;

  /// Whether [entity] is drawn as line art with no entity behind it.
  static bool isBare(Entity entity) =>
      entity.iconPath == null && entity.svg != null;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          entity.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
    final path = entity.iconPath;
    if (path == null) {
      return switch (entity.svg) {
        null => fallback,
        final svg => SvgPicture.string(svg, fit: BoxFit.contain),
      };
    }
    final image = Image(
      image: pictureAt(path),
      fit: entity.wideIcon ? BoxFit.cover : BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
    return entity.wideIcon
        ? image
        : Padding(padding: EdgeInsets.all(padding), child: image);
  }
}

/// The face of an entity that opens a popup: the user's picture, else the first
/// few entities inside, else a folder drawn in outline.
class FolderArt extends StatelessWidget {
  const FolderArt({super.key, required this.entry});

  final PanelEntry entry;

  static bool isBare(PanelEntry entry) =>
      entry.icon == null && entry.preview.isEmpty;

  static const _outline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
      'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '<path d="M46 30a5 5 0 0 1 5-5h18l8 9h32a5 5 0 0 1 5 5v26a5 5 0 0 1-5 '
      '5H51a5 5 0 0 1-5-5z"/></svg>';

  @override
  Widget build(BuildContext context) {
    if (entry.icon case final icon?) {
      return Image(
        image: pictureAt(icon),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SvgPicture.string(_outline),
      );
    }
    if (entry.preview.isEmpty) return SvgPicture.string(_outline);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        spacing: 4,
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                spacing: 4,
                children: [
                  for (var i = row * 2; i < row * 2 + 2; i++)
                    Expanded(
                      child: i < entry.preview.length
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: EntityArt(
                                entity: entry.preview[i],
                                padding: 2,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
