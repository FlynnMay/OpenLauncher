import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/packs/pack_setting.dart';

/// Content installed as one unit: a `.zip` holding `pack.json`, fonts in
/// `fonts/`, icon sets in `icons/`, pictures in `images/`, and JSON in
/// `entities/`, `sources/`, `generators/`, `prefabs/` and `screens/`.
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
    this.categories = const {},
    this.settings = const [],
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

  /// What its entity categories are called, in the order they are listed.
  final Map<String, String> categories;

  /// What it asks the user for; the values are `packSettings` in the config,
  /// and a secret's is kept apart.
  final List<PackSetting> settings;

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
        categories: {
          if (json['categories'] case final Map<Object?, Object?> categories)
            for (final MapEntry(:key, :value) in categories.entries)
              if (key is String && value is String) key: value,
        },
        settings: PackSetting.listFromJson(json['settings']),
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
    'categories': categories,
    if (settings.isNotEmpty)
      'settings': {for (final s in settings) s.key: s.toJson()},
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
    categories: categories,
    settings: settings,
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

  /// What [packs] call entity categories, in the order they list them; the
  /// first to name one names it.
  static Map<String, String> categoriesOf(Iterable<Pack> packs) {
    final named = <String, String>{};
    for (final pack in packs) {
      for (final MapEntry(:key, :value) in pack.categories.entries) {
        named.putIfAbsent(key, () => value);
      }
    }
    return named;
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
      mapEquals(other.categories, categories) &&
      listEquals(other.settings, settings) &&
      other.builtIn == builtIn &&
      other.bytes == bytes &&
      listEquals(other.files, files);

  @override
  int get hashCode => Object.hash(id, version, bytes);
}
