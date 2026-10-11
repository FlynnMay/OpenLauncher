import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher/features/home/picture.dart';

/// The wallpapers and their rotation.
class WallpaperSettings extends ConsumerStatefulWidget {
  const WallpaperSettings({super.key});

  static const max = 12;

  /// Rotation intervals, in minutes.
  static const turns = {
    0: 'Stay on the first',
    1: 'Every minute',
    5: 'Every 5 minutes',
    15: 'Every 15 minutes',
    30: 'Every half hour',
    60: 'Every hour',
    180: 'Every 3 hours',
    1440: 'Every day',
  };

  @override
  ConsumerState<WallpaperSettings> createState() => _WallpaperSettingsState();
}

class _WallpaperSettingsState extends ConsumerState<WallpaperSettings>
    with Busy<WallpaperSettings> {
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(tvApiProvider);
    final state = ref.watch(tvStateProvider).value;
    final wallpapers = state?.wallpapers ?? const [];
    final every = state?.wallpaperEvery ?? 0;
    return Section('Wallpaper', [
      ImageCarousel(
        max: WallpaperSettings.max,
        empty: 'A plain background',
        addLabel: 'Add a picture or video',
        firstLabel: every == 0
            ? 'Make this the wallpaper'
            : 'Show this one first',
        busy: busy,
        images: [
          for (final (:id, :wallpaper) in wallpapers)
            CarouselImage(
              id: id,
              child: switch (wallpaper.kind) {
                WallpaperKind.image => Image(
                  image: ResizeImage(pictureAt(wallpaper.path), width: 640),
                  fit: BoxFit.cover,
                ),
                WallpaperKind.video => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Icon(Icons.movie_outlined, size: 32),
                      Text('Video'),
                    ],
                  ),
                ),
              },
            ),
        ],
        onAdd: () => whileBusy(() async {
          final file = await pickFile(
            accept: 'image/*,video/mp4,video/webm,.mkv',
          );
          if (file != null) await api.addWallpaper(file);
        }),
        onRemove: (id) => whileBusy(() => api.removeWallpaper(id)),
        onFirst: (id) => whileBusy(
          () => api.arrangeWallpapers(
            order: [
              id,
              for (final other in wallpapers)
                if (other.id != id) other.id,
            ],
          ),
        ),
      ),
      if (wallpapers.length > 1)
        LabelledRow(
          'Change',
          ChoiceBox<int>(
            value: WallpaperSettings.turns.containsKey(every) ? every : null,
            choices: WallpaperSettings.turns,
            onChanged: (minutes) =>
                whileBusy(() => api.arrangeWallpapers(every: minutes)),
          ),
        ),
    ]);
  }
}
