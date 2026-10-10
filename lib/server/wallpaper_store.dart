import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/config_controller.dart';
import 'custom_icons.dart';

/// Where the uploaded wallpaper is kept.
final wallpaperDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'wallpaper'));
});

final wallpaperStoreProvider = Provider<WallpaperStore>(WallpaperStore.new);

enum WallpaperUpload { saved, tooLarge, unsupported }

/// Recognises MP4, WebM and Matroska by their leading bytes. Returns the file
/// extension, or null if [header] is none of them.
String? sniffVideoExtension(Uint8List header) {
  bool has(String ascii, int offset) {
    if (header.length < offset + ascii.length) return false;
    for (var i = 0; i < ascii.length; i++) {
      if (header[offset + i] != ascii.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (has('ftyp', 4)) return 'mp4';
  const ebml = [0x1A, 0x45, 0xDF, 0xA3];
  if (header.length >= 4 && [0, 1, 2, 3].every((i) => header[i] == ebml[i])) {
    // WebM is Matroska with its own document type, named near the start.
    for (var i = 4; i < header.length - 3; i++) {
      if (has('webm', i)) return 'webm';
    }
    return 'mkv';
  }
  return null;
}

String wallpaperContentType(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.mp4' => 'video/mp4',
      '.webm' => 'video/webm',
      '.mkv' => 'video/x-matroska',
      final extension => imageContentType(extension.replaceFirst('.', '')),
    };

/// Stores the uploaded wallpaper and points the config at it.
class WallpaperStore {
  WallpaperStore(this._ref);

  static const maxBytes = 300 * 1024 * 1024;

  // Enough of the file to recognise every supported format.
  static const _headerBytes = 64;

  final Ref _ref;

  /// Writes [body] straight to disk (videos are too big to hold in memory)
  /// and makes it the wallpaper if it is a supported image or video.
  Future<WallpaperUpload> save(Stream<List<int>> body) async {
    final dir = await _ref.read(wallpaperDirProvider.future);
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temp = File(p.join(dir.path, 'upload-$stamp.tmp'));
    final header = BytesBuilder();
    var length = 0;
    final sink = temp.openWrite();
    try {
      await for (final chunk in body) {
        length += chunk.length;
        if (length > maxBytes) break;
        if (header.length < _headerBytes) header.add(chunk);
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    final start = header.takeBytes();
    final extension = length > maxBytes
        ? null
        : sniffImageExtension(start) ?? sniffVideoExtension(start);
    if (extension == null) {
      await temp.delete();
      return length > maxBytes
          ? WallpaperUpload.tooLarge
          : WallpaperUpload.unsupported;
    }

    // A fresh name per upload, so players and caches never show the old one.
    final file = await temp.rename(
      p.join(dir.path, 'wallpaper-$stamp.$extension'),
    );
    final previous = (await _ref.read(configProvider.future)).wallpaper;
    await _ref.read(configProvider.notifier).setWallpaper(file.path);
    await _deleteIfOurs(previous, dir);
    return WallpaperUpload.saved;
  }

  /// Returns to the plain background.
  Future<void> clear() async {
    final previous = (await _ref.read(configProvider.future)).wallpaper;
    await _ref.read(configProvider.notifier).setWallpaper(null);
    await _deleteIfOurs(previous, await _ref.read(wallpaperDirProvider.future));
  }

  Future<void> _deleteIfOurs(String? path, Directory dir) async {
    if (path == null || !p.isWithin(dir.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
