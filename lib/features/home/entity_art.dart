import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/picture.dart';

/// An entity's picture: artwork, line art, or its name.
class EntityArt extends StatelessWidget {
  const EntityArt({super.key, required this.entity, this.padding = 14});

  final Entity entity;

  /// Padding around a square icon.
  final double padding;

  /// Whether [entity] is line art.
  static bool isBare(Entity entity) =>
      entity.data[Entity.shape] == Entity.lineArt;

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
    final path = entity.data[Entity.icon];
    if (path is! String) return fallback;
    if (isBare(entity)) return SvgPicture.string(path, fit: BoxFit.contain);
    final wide = entity.data[Entity.shape] == Entity.banner;
    final image = Image(
      image: pictureAt(path),
      fit: wide ? BoxFit.cover : BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
    return wide
        ? image
        : Padding(padding: EdgeInsets.all(padding), child: image);
  }
}

/// A folder's picture: the user's, else a preview of its contents, else an
/// outline.
class FolderArt extends ConsumerWidget {
  const FolderArt({super.key, required this.folder});

  final String folder;

  /// How many entities the preview shows.
  static const _shown = 4;

  static const _outline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
      'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '<path d="M46 30a5 5 0 0 1 5-5h18l8 9h32a5 5 0 0 1 5 5v26a5 5 0 0 1-5 '
      '5H51a5 5 0 0 1-5-5z"/></svg>';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = ref.watch(
      configProvider.select(
        (config) => config.value?.iconOverrides[Layout.iconKey(folder)],
      ),
    );
    if (icon != null) {
      return Image(
        image: pictureAt(icon),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SvgPicture.string(_outline),
      );
    }
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final preview = [
      for (final item
          in ref.watch(layoutViewProvider).value?.pane(folder)?.contents ??
              const <Component>[])
        ?entities.byId(item.handed.firstOrNull),
    ].take(_shown).toList();
    if (preview.isEmpty) return SvgPicture.string(_outline);
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
                      child: i < preview.length
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: EntityArt(entity: preview[i], padding: 2),
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
