import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/config_controller.dart';

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

/// The current wallpaper, or null for a plain background.
final wallpaperProvider = Provider<Wallpaper?>(
  (ref) => Wallpaper.fromPath(ref.watch(configProvider).value?.wallpaper),
);
