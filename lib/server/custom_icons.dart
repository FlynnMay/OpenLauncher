import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where user-uploaded card images are kept.
final customIconDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'custom-icons'));
});

final customIconsProvider = Provider<CustomIcons>(CustomIcons.new);

/// Image formats Flutter can decode, recognised by their leading bytes.
/// Returns the file extension, or null if [bytes] is not a supported image.
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

String imageContentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'jpg' => 'image/jpeg',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  _ => 'application/octet-stream',
};

/// Stores uploaded card images and points the config at them.
class CustomIcons {
  CustomIcons(this._ref);

  final Ref _ref;

  /// Saves [bytes] as the image for [cardId]. Returns false if they are not
  /// a supported image.
  Future<bool> set(String cardId, Uint8List bytes) async {
    final extension = sniffImageExtension(bytes);
    if (extension == null) return false;
    final dir = await _ref.read(customIconDirProvider.future);
    await dir.create(recursive: true);
    // A fresh name per upload, so image caches never show the old picture.
    final name =
        '${cardId.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_')}'
        '-${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);

    final previous = await _currentPath(cardId);
    await _ref.read(configProvider.notifier).setIconOverride(cardId, file.path);
    await _deleteIfOurs(previous, dir);
    return true;
  }

  /// Returns [cardId] to its automatic image.
  Future<void> clear(String cardId) async {
    final previous = await _currentPath(cardId);
    await _ref.read(configProvider.notifier).setIconOverride(cardId, null);
    await _deleteIfOurs(
      previous,
      await _ref.read(customIconDirProvider.future),
    );
  }

  Future<String?> _currentPath(String cardId) async =>
      (await _ref.read(configProvider.future)).iconOverrides[cardId];

  Future<void> _deleteIfOurs(String? path, Directory dir) async {
    if (path == null || !p.isWithin(dir.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
