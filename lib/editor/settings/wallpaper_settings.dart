import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// The wallpapers and their rotation.
class WallpaperSettings extends ConsumerStatefulWidget {
  const WallpaperSettings({super.key});

  /// Rotation intervals, in minutes.
  static final turns = {
    for (final MapEntry(:key, :value) in wallpaperTurns.entries)
      int.parse(key): value,
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
    Future<void> setWallpapers(List<String> paths) => whileBusy(
      () => setSettings(context, ref, {'wallpapers': List.unmodifiable(paths)}),
    );
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
          await setSettings(context, ref, {
            'wallpapers': [...wallpapers, url],
          });
        }),
        // The file stays on the TV; Media deletes it.
        onRemove: (url) => setWallpapers([
          for (final other in wallpapers)
            if (other != url) other,
        ]),
        onFirst: (url) => setWallpapers([
          url,
          for (final other in wallpapers)
            if (other != url) other,
        ]),
      ),
      if (wallpapers.length > 1)
        LabelledRow(
          'Change',
          ChoiceBox<int>(
            value: WallpaperSettings.turns.containsKey(every) ? every : null,
            choices: WallpaperSettings.turns,
            onChanged: (minutes) => whileBusy(
              () => setSettings(context, ref, {
                'wallpaperEvery': minutes.clamp(
                  0,
                  LauncherConfig.maxWallpaperEvery,
                ),
              }),
            ),
          ),
        ),
    ]);
  }
}
