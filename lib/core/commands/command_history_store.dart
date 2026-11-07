import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps what each session can undo and redo, so it survives the app
/// restarting. What it keeps is JSON the history writes and reads itself.
abstract interface class CommandHistoryStore {
  /// Null if nothing was kept, or it cannot be read.
  Future<Object?> load();

  Future<void> save(Object? history);
}

final commandHistoryStoreProvider = Provider<CommandHistoryStore>(
  (ref) => FileCommandHistoryStore(),
);

/// `command_history.json` in the app support dir, written atomically, one save
/// at a time.
class FileCommandHistoryStore implements CommandHistoryStore {
  /// [dir] is overridden in tests.
  FileCommandHistoryStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dir;
  Future<void> _writing = Future.value();

  Future<File> _file() async =>
      File(p.join((await _dir()).path, 'command_history.json'));

  @override
  Future<Object?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on Object catch (error) {
      debugPrint('command_history.json unreadable, starting empty: $error');
      return null;
    }
  }

  /// Encoded now, so saves land in call order with the history as it was.
  @override
  Future<void> save(Object? history) {
    final text = jsonEncode(history);
    final write = _writing.then((_) => _write(text));
    _writing = write.catchError((Object _) {});
    return write;
  }

  Future<void> _write(String text) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }
}

/// For tests.
class MemoryCommandHistoryStore implements CommandHistoryStore {
  Object? _history;

  @override
  Future<Object?> load() async => _history;

  @override
  Future<void> save(Object? history) async =>
      _history = jsonDecode(jsonEncode(history));
}
