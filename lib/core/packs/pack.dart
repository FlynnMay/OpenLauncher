import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Content installed as one unit: a `.zip` holding `pack.json`, fonts in
/// `fonts/`, icon sets in `icons/`, pictures in `images/`, and JSON in
/// `entities/`, `sources/`, `generators/`, `prefabs/` and `layouts/`.
@immutable
class Pack {
  const Pack({
    required this.id,
    required this.name,
    this.version = '',
    this.author = '',
    this.licence = '',
    this.source = '',
    this.requires = const [],
    this.builtIn = false,
    this.bytes = 0,
    this.files = const [],
  });

  static final _id = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');

  /// Whether [id] can name a pack or one of its icon sets.
  static bool validId(Object? id) => id is String && _id.hasMatch(id);

  final String id, name, version, author, licence;

  /// Where it is made, e.g. its repository.
  final String source;

  /// The packs it names, which must be installed first.
  final List<String> requires;

  /// Ships with the launcher, so cannot be removed: the one way it differs.
  final bool builtIn;

  /// Its size once unpacked.
  final int bytes;

  /// What it holds besides `pack.json`, by path.
  final List<String> files;

  /// The names of the files in [folder], without extensions.
  List<String> named(String folder) => [
    for (final path in files)
      if (path.startsWith('$folder/'))
        path.substring(folder.length + 1, path.lastIndexOf('.')),
  ];

  /// Ids of its icon sets: the files in `icons/`.
  List<String> get iconSets => named('icons');

  /// From `pack.json`, or as the editor is sent it.
  static Pack? fromJson(Object? json) {
    if (json case {'id': final String id} when validId(id)) {
      String text(String key) => switch (json[key]) {
        final String text => text,
        final num number => '$number',
        _ => '',
      };
      return Pack(
        id: id,
        name: text('name').isEmpty ? id : text('name'),
        version: text('version'),
        author: text('author'),
        licence: text('licence'),
        source: text('source'),
        requires: [
          if (json['requires'] case final List<Object?> packs)
            for (final pack in packs)
              if (validId(pack)) pack as String,
        ],
        builtIn: json['builtIn'] == true,
        bytes: switch (json['bytes']) {
          final num bytes => bytes.toInt(),
          _ => 0,
        },
        files: [
          if (json['files'] case final List<Object?> files)
            for (final file in files)
              if (file is String) file,
        ],
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'licence': licence,
    'source': source,
    'requires': requires,
    'builtIn': builtIn,
    'bytes': bytes,
    'files': files,
  };

  Pack copyWith({bool? builtIn, int? bytes, List<String>? files}) => Pack(
    id: id,
    name: name,
    version: version,
    author: author,
    licence: licence,
    source: source,
    requires: requires,
    builtIn: builtIn ?? this.builtIn,
    bytes: bytes ?? this.bytes,
    files: files ?? this.files,
  );

  /// How many times [saved] (a config as JSON) names something of this
  /// pack: an icon of its sets, or anything by its id.
  int usesIn(Object? saved) {
    final text = jsonEncode(saved);
    return {id, ...iconSets}.fold(
      0,
      (uses, prefix) =>
          uses +
          RegExp('(?<![\\w:-])${RegExp.escape(prefix)}:[a-z0-9_]')
              .allMatches(text)
              .length,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Pack &&
      other.id == id &&
      other.name == name &&
      other.version == version &&
      other.author == author &&
      other.licence == licence &&
      other.source == source &&
      listEquals(other.requires, requires) &&
      other.builtIn == builtIn &&
      other.bytes == bytes &&
      listEquals(other.files, files);

  @override
  int get hashCode => Object.hash(id, version, bytes);
}
