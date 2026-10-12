import 'package:flutter/material.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/features/home/picture.dart';

/// A small view of an uploaded file: the picture, or a mark for a video.
class MediaPreview extends StatelessWidget {
  const MediaPreview(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) => switch (Wallpaper.fromPath(url)?.kind) {
    WallpaperKind.image => Image(
      image: ResizeImage(pictureAt(url), width: 640),
      fit: BoxFit.cover,
    ),
    WallpaperKind.video => const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [Icon(Icons.movie_outlined, size: 32), Text('Video')],
      ),
    ),
    null => const Center(child: Icon(Icons.insert_drive_file_outlined)),
  };
}
