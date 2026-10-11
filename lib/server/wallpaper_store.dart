import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/server/custom_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the uploaded wallpaper is kept.
final wallpaperDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'wallpaper'));
});

final wallpaperStoreProvider = Provider<WallpaperStore>(WallpaperStore.new);

enum WallpaperUpload { saved, tooLarge, unsupported, tooMany }

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

/// Stores uploaded wallpapers and keeps the config's list of them. Each is
/// known to the page by its file name, which no other upload ever has.
class WallpaperStore {
  WallpaperStore(this._ref);

  static const maxBytes = 300 * 1024 * 1024;

  /// How many there can be at once.
  static const maxCount = 12;

  // Enough of the file to recognise every supported format.
  static const _headerBytes = 64;

  final Ref _ref;

  /// The name a wallpaper is known by.
  static String idOf(String path) => p.basename(path);

  Future<List<String>> _paths() async =>
      (await _ref.read(configProvider.future)).wallpapers;

  /// Writes [body] straight to disk (videos are too big to hold in memory)
  /// and, if it is a supported image or video, adds it after the wallpapers
  /// there are.
  Future<WallpaperUpload> add(Stream<List<int>> body) async {
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

    final previous = await _paths();
    final start = header.takeBytes();
    final extension = length > maxBytes
        ? null
        : sniffImageExtension(start) ?? sniffVideoExtension(start);
    if (extension == null || previous.length >= maxCount) {
      await temp.delete();
      return length > maxBytes
          ? WallpaperUpload.tooLarge
          : extension == null
          ? WallpaperUpload.unsupported
          : WallpaperUpload.tooMany;
    }

    // A fresh name per upload, so players and caches never show the old one.
    final file = await temp.rename(
      p.join(dir.path, 'wallpaper-$stamp.$extension'),
    );
    await _ref.read(configProvider.notifier).setWallpapers([
      ...previous,
      file.path,
    ]);
    return WallpaperUpload.saved;
  }

  /// Takes the wallpaper [id] away. False if there is none by that name.
  Future<bool> remove(String id) async {
    final paths = await _paths();
    final gone = paths.where((path) => idOf(path) == id).toList();
    if (gone.isEmpty) return false;
    await _ref.read(configProvider.notifier).setWallpapers([
      for (final path in paths)
        if (!gone.contains(path)) path,
    ]);
    await _delete(gone, await _ref.read(wallpaperDirProvider.future));
    return true;
  }

  /// Puts the wallpapers in the order of [ids]; any left out follow in the
  /// order they were in.
  Future<void> arrange(List<String> ids) async {
    final paths = await _paths();
    int place(String path) => switch (ids.indexOf(idOf(path))) {
      -1 => ids.length + paths.indexOf(path),
      final index => index,
    };
    await _ref
        .read(configProvider.notifier)
        .setWallpapers(
          [...paths]..sort((a, b) => place(a).compareTo(place(b))),
        );
  }

  /// Returns to the plain background.
  Future<void> clear() async {
    final previous = await _paths();
    await _ref.read(configProvider.notifier).setWallpapers(const []);
    await _delete(previous, await _ref.read(wallpaperDirProvider.future));
  }

  /// Deletes those of [paths] that are files of ours.
  Future<void> _delete(List<String> paths, Directory dir) async {
    for (final path in paths) {
      if (!p.isWithin(dir.path, path)) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
