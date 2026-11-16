import 'package:flutter/foundation.dart';
import 'package:openlauncher_domain/packs/pack_kind.dart';

export 'package:openlauncher_domain/packs/pack_kind.dart';

/// One object in a pack's file, by the name it goes by in the pack.
@immutable
class PackItem {
  const PackItem(this.name, this.json, this.where);

  final String name;
  final Map<String, Object?> json;

  /// For an error to say: the file, and the name in it if it holds several.
  final String where;
}

/// Where a pack keeps what it holds: a folder for each feature, with a file
/// for each kind of thing in it, `weather/prefab.jsonc`. A file holds one
/// object, named for its folder, or several by name. A kind with many
/// objects can also be a folder of files, `weather/prefab/card.jsonc`.
/// `defs.jsonc` in a feature's folder, or the pack's own, holds chunks its
/// files can reuse.
@immutable
class PackFile {
  const PackFile(this.feature, this.kind, [this.name]);

  /// The folder it is in.
  final String feature;
  final PackKind kind;

  /// The file's name when it is in a folder of its kind.
  final String? name;

  static const _word = r'[a-z0-9][a-z0-9_-]*';

  static final _flat = RegExp('^($_word)/([a-z]+)\\.jsonc?\$');
  static final _inFolder = RegExp('^($_word)/([a-z]+)/($_word)\\.jsonc?\$');
  static final _defs = RegExp('^($_word)/defs\\.jsonc?\$');

  /// What each folder at the top of a pack is for, and cannot be a feature.
  static const reservedFolders = {'fonts', 'icons', 'images'};

  /// The folders packs were laid out by before features had their own.
  static const oldFolders = {
    'entities',
    'fields',
    'sources',
    'generators',
    'prefabs',
    'screens',
  };

  /// What [path] is, if it is a file of a feature.
  static PackFile? of(String path) {
    final match = _flat.firstMatch(path) ?? _inFolder.firstMatch(path);
    if (match == null) return null;
    final feature = match[1]!;
    if (reservedFolders.contains(feature) || oldFolders.contains(feature)) {
      return null;
    }
    final kind = PackKind.values.where((kind) => kind.name == match[2]);
    if (kind.isEmpty) return null;
    return PackFile(
      feature,
      kind.first,
      match.groupCount > 2 ? match[3] : null,
    );
  }

  /// The feature whose `defs` file [path] is.
  static String? defsFeatureOf(String path) => _defs.firstMatch(path)?[1];

  /// Whether [path] is the pack's own `defs` file.
  static bool isPackDefs(String path) =>
      path == 'defs.json' || path == 'defs.jsonc';

  /// Whether [path] is in a folder of the old layout.
  static bool isOld(String path) =>
      oldFolders.contains(path.split('/').first) && path.contains('/');

  /// The objects in this file's [json], read from [path].
  List<PackItem> items(String path, Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('$path needs an object');
    }
    final one = {
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) key: value,
    };
    final several =
        one.isNotEmpty &&
        one.values.every((value) => value is Map) &&
        !kind.ownKeys.any(one.containsKey);
    if (!several) return [PackItem(name ?? feature, one, path)];
    return [
      for (final MapEntry(:key, :value) in one.entries)
        PackItem(key, {
          for (final MapEntry(key: inner, :value) in (value as Map).entries)
            if (inner is String) inner: value,
        }, '$path#/$key'),
    ];
  }
}
