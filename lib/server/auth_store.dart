import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A browser that has paired with the TV. The session token is kept only as
/// its SHA-256 hash, so a leak of the file cannot be replayed.
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

  /// What the editor is shown: everything but the hash.
  Map<String, Object?> forEditor() => {
    'id': id,
    'label': label,
    'added': added.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };

  static TrustedDevice? fromJson(Object? json) {
    if (json
        case {
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

/// Where the trusted-device list is kept. Never served and never part of the
/// editor-readable config.
abstract interface class AuthStore {
  Future<List<TrustedDevice>> load();
  Future<void> save(List<TrustedDevice> devices);
}

final authStoreProvider = Provider<AuthStore>((ref) => FileAuthStore());

/// `auth.json` in the app support dir, written atomically.
class FileAuthStore implements AuthStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'auth.json'));
  }

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

  @override
  Future<void> save(List<TrustedDevice> devices) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'devices': [for (final d in devices) d.toJson()]}),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

/// Keeps the list in memory only. Used in tests.
class MemoryAuthStore implements AuthStore {
  List<TrustedDevice> _devices = const [];

  @override
  Future<List<TrustedDevice>> load() async => _devices;

  @override
  Future<void> save(List<TrustedDevice> devices) async =>
      _devices = List.unmodifiable(devices);
}
