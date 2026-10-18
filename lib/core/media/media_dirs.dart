import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Where the file [id] kept for its use is, as a picture or video reads it.
/// The editor reaches them by URL.
final mediaPathProvider =
    FutureProvider<String Function(MediaUse use, String id)>((ref) async {
      final dirs = {
        for (final use in MediaUse.values)
          use: await ref.watch(mediaDirProvider(use).future),
      };
      return (use, id) => p.join(dirs[use]!.path, id);
    });
