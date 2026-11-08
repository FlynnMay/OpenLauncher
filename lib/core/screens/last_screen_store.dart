import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the id of the screen shown last, for a startup that remembers. It is
/// not part of the saved config: it changes on every screen change and is no
/// one's edit.
abstract interface class LastScreenStore {
  /// Null if nothing was kept, or it cannot be read.
  Future<String?> load();

  Future<void> save(String id);
}

final lastScreenStoreProvider = Provider<LastScreenStore>(
  (ref) => FileLastScreenStore(),
);

/// `last_screen.txt` in the app support dir.
class FileLastScreenStore implements LastScreenStore {
  /// [dir] is overridden in tests.
  FileLastScreenStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dir;

  Future<File> _file() async =>
      File(p.join((await _dir()).path, 'last_screen.txt'));

  @override
  Future<String?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final id = (await file.readAsString()).trim();
      return id.isEmpty ? null : id;
    } on Object catch (error) {
      debugPrint('last_screen.txt unreadable, starting without: $error');
      return null;
    }
  }

  @override
  Future<void> save(String id) async {
    try {
      await (await _file()).writeAsString(id, flush: true);
    } on Object catch (error) {
      debugPrint('Could not keep the last screen: $error');
    }
  }
}

/// For tests.
class MemoryLastScreenStore implements LastScreenStore {
  MemoryLastScreenStore([this._id]);

  String? _id;

  @override
  Future<String?> load() async => _id;

  @override
  Future<void> save(String id) async => _id = id;
}
