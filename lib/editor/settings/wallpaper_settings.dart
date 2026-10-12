import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// The wallpapers and their rotation.
class WallpaperSettings extends ConsumerStatefulWidget {
  const WallpaperSettings({super.key});

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
    final config = ref.watch(configProvider).value;
    final wallpapers = config?.wallpapers ?? const <String>[];
    final every = config?.wallpaperEvery ?? 0;
    Future<void> change(
      Future<void> Function(ConfigController controller) how,
    ) => whileBusy(() => changeConfig(context, ref, how));
    return Section('Wallpaper', [
      ImageCarousel(
        max: LauncherConfig.maxWallpapers,
        empty: 'A plain background',
        addLabel: 'Add a picture or video',
        firstLabel: every == 0
            ? 'Make this the wallpaper'
            : 'Show this one first',
        busy: busy,
        images: [
          for (final url in wallpapers)
            CarouselImage(id: url, child: MediaPreview(url)),
        ],
        onAdd: () => whileBusy(() async {
          final file = await pickFile(
            accept: 'image/*,video/mp4,video/webm,.mkv',
          );
          if (file == null) return;
          final url = await api.upload(file, wallpaper: true);
          if (!context.mounted) return;
          await changeConfig(
            context,
            ref,
            (c) => c.setWallpapers([...wallpapers, url]),
          );
        }),
        // The file stays on the TV; Media deletes it.
        onRemove: (url) => change(
          (c) => c.setWallpapers([
            for (final other in wallpapers)
              if (other != url) other,
          ]),
        ),
        onFirst: (url) => change(
          (c) => c.setWallpapers([
            url,
            for (final other in wallpapers)
              if (other != url) other,
          ]),
        ),
      ),
      if (wallpapers.length > 1)
        LabelledRow(
          'Change',
          ChoiceBox<int>(
            value: WallpaperSettings.turns.containsKey(every) ? every : null,
            choices: WallpaperSettings.turns,
            onChanged: (minutes) => change((c) => c.setWallpaperEvery(minutes)),
          ),
        ),
    ]);
  }
}
