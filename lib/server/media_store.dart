import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What an upload is for: where it is kept and what it may be.
enum MediaUse {
  picture('custom-icons', 8 * 1024 * 1024, video: false),
  wallpaper('wallpaper', 300 * 1024 * 1024, video: true);

  const MediaUse(this.folder, this.maxBytes, {required this.video});

  final String folder;
  final int maxBytes;
  final bool video;
}

final mediaDirProvider = FutureProvider.family<Directory, MediaUse>((
  ref,
  use,
) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, use.folder));
});

final mediaStoreProvider = Provider<MediaStore>(MediaStore.new);

/// An uploaded file; [used] if the config points at it.
typedef MediaFile = ({String id, int bytes, bool used});

/// Why an upload or a delete was turned down, as an HTTP status.
class MediaRefused implements Exception {
  const MediaRefused(this.status, this.message);

  final int status;
  final String message;
}

/// The extension for a supported image, sniffed from its first bytes; null
/// otherwise.
String? sniffImageExtension(Uint8List bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'webp';
  }
  return null;
}

/// The extension for MP4, WebM or Matroska, sniffed from [header]; null
/// otherwise.
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

/// Every uploaded file, by its unique file name. A file is only ever deleted
/// by [delete] and [deleteUnused]; the config dropping it leaves it here.
class MediaStore {
  MediaStore(this._ref);

  // Enough of the file to recognise every supported format.
  static const _headerBytes = 64;

  static const _partial = '.tmp';

  final Ref _ref;

  static String idOf(String path) => p.basename(path);

  /// [open] with its file paths as ids, as the editor is sent them.
  static Map<String, Object?> withIds(Map<String, Object?> open) => {
    ...open,
    if (open['iconOverrides'] case final Map<Object?, Object?> pictures)
      'iconOverrides': {
        for (final MapEntry(:key, :value) in pictures.entries)
          key: idOf(value as String),
      },
    if (open['wallpapers'] case final List<Object?> wallpapers)
      'wallpapers': [for (final path in wallpapers) idOf(path as String)],
  };

  /// [sent] with its file ids as paths; an id with no file is left out.
  Future<Map<String, Object?>> withPaths(Map<String, Object?> sent) async => {
    ...sent,
    if (sent['iconOverrides'] case final Map<Object?, Object?> pictures)
      'iconOverrides': {
        for (final MapEntry(:key, :value) in pictures.entries)
          key: ?await pathOf(value),
      },
    if (sent['wallpapers'] case final List<Object?> wallpapers)
      'wallpapers': [for (final id in wallpapers) ?await pathOf(id)],
  };

  Future<Directory> _dir(MediaUse use) =>
      _ref.read(mediaDirProvider(use).future);

  Future<List<File>> _files() async => [
    for (final use in MediaUse.values)
      if (await _dir(use) case final dir when await dir.exists())
        await for (final entry in dir.list())
          if (entry is File && !entry.path.endsWith(_partial)) entry,
  ];

  Future<Set<String>> _usedIds() async {
    final config = await _ref.read(configProvider.future);
    return {
      for (final path in config.iconOverrides.values) idOf(path),
      for (final path in config.wallpapers) idOf(path),
    };
  }

  /// Newest first.
  Future<List<MediaFile>> list() async {
    final used = await _usedIds();
    final files = [
      for (final file in await _files()) (file: file, stat: await file.stat()),
    ]..sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    return [
      for (final (:file, :stat) in files)
        (
          id: idOf(file.path),
          bytes: stat.size,
          used: used.contains(idOf(file.path)),
        ),
    ];
  }

  Future<String?> pathOf(Object? id) async {
    if (id is! String || id != p.basename(id) || id.endsWith(_partial)) {
      return null;
    }
    for (final use in MediaUse.values) {
      final file = File(p.join((await _dir(use)).path, id));
      if (await file.exists()) return file.path;
    }
    return null;
  }

  /// Streams [body] to disk and returns its id. Nothing points at it yet.
  Future<String> add(Stream<List<int>> body, MediaUse use) async {
    final dir = await _dir(use);
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temp = File(p.join(dir.path, 'upload-$stamp$_partial'));
    final header = BytesBuilder();
    var length = 0;
    final sink = temp.openWrite();
    try {
      await for (final chunk in body) {
        length += chunk.length;
        if (length > use.maxBytes) break;
        if (header.length < _headerBytes) header.add(chunk);
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    final start = header.takeBytes();
    final extension = length > use.maxBytes
        ? null
        : sniffImageExtension(start) ??
              (use.video ? sniffVideoExtension(start) : null);
    if (extension == null) {
      await temp.delete();
      throw length > use.maxBytes
          ? MediaRefused(
              413,
              'File too large (${use.maxBytes ~/ (1024 * 1024)} MB max)',
            )
          : MediaRefused(
              415,
              use.video
                  ? 'Not a supported image (PNG, JPEG, GIF, WebP) or video '
                        '(MP4, WebM, MKV)'
                  : 'Not a PNG, JPEG, GIF or WebP image',
            );
    }
    // A new name per upload defeats caches.
    final file = await temp.rename(
      p.join(dir.path, '${use.name}-$stamp.$extension'),
    );
    return idOf(file.path);
  }

  /// Deletes [id] unless the config points at it.
  Future<void> delete(String id) async {
    final path = await pathOf(id);
    if (path == null) throw const MediaRefused(404, 'No such file');
    if ((await _usedIds()).contains(id)) {
      throw const MediaRefused(409, 'That file is in use');
    }
    await File(path).delete();
  }

  /// Deletes every file the config does not point at; returns how many.
  Future<int> deleteUnused() async {
    final used = await _usedIds();
    var deleted = 0;
    for (final file in await _files()) {
      if (used.contains(idOf(file.path))) continue;
      await file.delete();
      deleted++;
    }
    return deleted;
  }
}
