import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A paired browser; only its token's hash is stored.
@immutable
class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.tokenHash,
    required this.label,
    required this.added,
    required this.lastSeen,
  });

  final String id;
  final String tokenHash;
  final String label;
  final DateTime added;
  final DateTime lastSeen;

  TrustedDevice seenAt(DateTime when) => TrustedDevice(
    id: id,
    tokenHash: tokenHash,
    label: label,
    added: added,
    lastSeen: when,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'tokenHash': tokenHash,
    'label': label,
    'added': added.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };

  /// Without the hash.
  Map<String, Object?> forEditor() => {
    'id': id,
    'label': label,
    'added': added.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };

  static TrustedDevice? fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'tokenHash': final String tokenHash,
      'label': final String label,
      'added': final String added,
      'lastSeen': final String lastSeen,
    }) {
      final addedAt = DateTime.tryParse(added);
      final seenAt = DateTime.tryParse(lastSeen);
      if (addedAt == null || seenAt == null) return null;
      return TrustedDevice(
        id: id,
        tokenHash: tokenHash,
        label: label,
        added: addedAt,
        lastSeen: seenAt,
      );
    }
    return null;
  }
}

/// Never served, and not part of the config.
abstract interface class AuthStore {
  Future<List<TrustedDevice>> load();
  Future<void> save(List<TrustedDevice> devices);
}

final authStoreProvider = Provider<AuthStore>((ref) => FileAuthStore());

/// `auth.json` in the app support dir, written atomically, one save at a time.
class FileAuthStore implements AuthStore {
  /// [dir] is overridden in tests.
  FileAuthStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dir;
  Future<void> _writing = Future.value();

  Future<File> _file() async => File(p.join((await _dir()).path, 'auth.json'));

  @override
  Future<List<TrustedDevice>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final json = jsonDecode(await file.readAsString());
      return [
        if (json case {'devices': final List<Object?> devices})
          for (final device in devices) ?TrustedDevice.fromJson(device),
      ];
    } on Object catch (e) {
      debugPrint('auth.json unreadable, starting empty: $e');
      return const [];
    }
  }

  /// Encoded now, so saves land in call order with the list as it was.
  @override
  Future<void> save(List<TrustedDevice> devices) {
    final text = jsonEncode({
      'devices': [for (final d in devices) d.toJson()],
    });
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
class MemoryAuthStore implements AuthStore {
  List<TrustedDevice> _devices = const [];

  @override
  Future<List<TrustedDevice>> load() async => _devices;

  @override
  Future<void> save(List<TrustedDevice> devices) async =>
      _devices = List.unmodifiable(devices);
}
