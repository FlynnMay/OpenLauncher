import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The values of packs' secret settings: pack id -> key -> value. Kept apart
/// from the config, so never in `config.json`, a saved state or an export,
/// and never sent to the editor.
abstract interface class SecretStore {
  Future<Map<String, Map<String, String>>> load();
  Future<void> save(Map<String, Map<String, String>> secrets);
}

final secretStoreProvider = Provider<SecretStore>((ref) => FileSecretStore());

final packSecretsProvider =
    AsyncNotifierProvider<PackSecrets, Map<String, Map<String, String>>>(
      PackSecrets.new,
    );

/// The only place secrets change.
class PackSecrets extends AsyncNotifier<Map<String, Map<String, String>>> {
  @override
  Future<Map<String, Map<String, String>>> build() =>
      ref.watch(secretStoreProvider).load();

  Future<void> _update(
    Map<String, Map<String, String>> Function(Map<String, Map<String, String>>)
    change,
  ) async {
    final next = change(await future);
    state = AsyncData(next);
    await ref.read(secretStoreProvider).save(next);
  }

  /// Keeps [value] as [key] of [pack]; blank clears it.
  Future<void> set(String pack, String key, String value) => _update((all) {
    final mine = {...?all[pack]};
    if (value.isEmpty) {
      mine.remove(key);
    } else {
      mine[key] = value;
    }
    return {
      for (final MapEntry(key: id, value: kept) in all.entries)
        if (id != pack) id: kept,
      if (mine.isNotEmpty) pack: mine,
    };
  });

  /// Forgets everything kept for [pack].
  Future<void> forget(String pack) => _update((all) => {...all}..remove(pack));
}

/// `secrets.json` in the app support dir, written atomically, one save at a
/// time.
class FileSecretStore implements SecretStore {
  /// [dir] is overridden in tests.
  FileSecretStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dir;
  Future<void> _writing = Future.value();

  Future<File> _file() async =>
      File(p.join((await _dir()).path, 'secrets.json'));

  @override
  Future<Map<String, Map<String, String>>> load() async {
    final file = await _file();
    if (!await file.exists()) return const {};
    try {
      return _byPack(jsonDecode(await file.readAsString()));
    } on Object catch (e) {
      debugPrint('secrets.json unreadable, starting empty: $e');
      return const {};
    }
  }

  /// Pack id -> its secrets, from the saved JSON; what is not text is left
  /// out.
  static Map<String, Map<String, String>> _byPack(Object? json) {
    if (json is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) key: _texts(value),
    };
  }

  static Map<String, String> _texts(Object? json) {
    if (json is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is String) key: value,
    };
  }

  @override
  Future<void> save(Map<String, Map<String, String>> secrets) {
    final text = jsonEncode(secrets);
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
class MemorySecretStore implements SecretStore {
  Map<String, Map<String, String>> _secrets = const {};

  @override
  Future<Map<String, Map<String, String>>> load() async => _secrets;

  @override
  Future<void> save(Map<String, Map<String, String>> secrets) async =>
      _secrets = secrets;
}
