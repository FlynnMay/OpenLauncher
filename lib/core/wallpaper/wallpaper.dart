import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:path/path.dart' as p;

enum WallpaperKind { image, video }

/// What is shown behind the home screen.
@immutable
class Wallpaper {
  const Wallpaper(this.path, this.kind);

  final String path;
  final WallpaperKind kind;

  /// File extensions the launcher can show, by kind. Animated GIF and WebP
  /// count as images: they animate without a video decoder.
  static const extensions = {
    'png': WallpaperKind.image,
    'jpg': WallpaperKind.image,
    'gif': WallpaperKind.image,
    'webp': WallpaperKind.image,
    'mp4': WallpaperKind.video,
    'webm': WallpaperKind.video,
    'mkv': WallpaperKind.video,
  };

  static Wallpaper? fromPath(String? path) {
    if (path == null) return null;
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    final kind = extensions[extension];
    return kind == null ? null : Wallpaper(path, kind);
  }

  @override
  bool operator ==(Object other) =>
      other is Wallpaper && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);
}

/// Every wallpaper there is, in the user's order.
final wallpapersProvider = Provider<List<Wallpaper>>(
  (ref) => [
    for (final path in ref.watch(configProvider).value?.wallpapers ?? const [])
      ?Wallpaper.fromPath(path),
  ],
);

/// How many minutes each wallpaper stays before the next; 0 for no turns.
final wallpaperEveryProvider = Provider<int>(
  (ref) => ref.watch(configProvider).value?.wallpaperEvery ?? 0,
);

/// Counts the turns taken since it was first asked, one every so many
/// minutes.
final _turnsProvider = StreamProvider.autoDispose.family<int, int>(
  (ref, minutes) =>
      Stream.periodic(Duration(minutes: minutes), (turn) => turn + 1),
);

/// The wallpaper to show now, or null for a plain background: the first,
/// or with turns switched on each of them for a while.
final wallpaperProvider = Provider<Wallpaper?>((ref) {
  final all = ref.watch(wallpapersProvider);
  if (all.isEmpty) return null;
  final every = ref.watch(wallpaperEveryProvider);
  if (every <= 0 || all.length < 2) return all.first;
  return all[(ref.watch(_turnsProvider(every)).value ?? 0) % all.length];
});
