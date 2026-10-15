import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/packs/icon_sets.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';
import 'package:openlauncher/core/sources/generator.dart';
import 'package:openlauncher/core/sources/source.dart';

/// A pack's entities, sources, generators and prefabs. A built-in pack may
/// use any id; another's ids start `<pack>:`.
@immutable
class PackContents {
  const PackContents(
    this.pack, {
    this.entities = const [],
    this.sources = const {},
    this.generators = const {},
    this.prefabs = const [],
  });

  static const folders = ['entities', 'sources', 'generators', 'prefabs'];

  final Pack pack;
  final List<Entity> entities;

  /// By file name.
  final Map<String, Source> sources;
  final Map<String, Generator> generators;

  final List<Prefab> prefabs;

  /// Whether [path] is one of the files read here.
  static bool reads(String path) =>
      folders.any((folder) => path.startsWith('$folder/'));

  /// Reads [files], JSON text by path. Throws a [FormatException] saying
  /// what is wrong.
  static PackContents parse(Pack pack, Map<String, String> files) {
    void own(String path, String id) {
      if (!pack.builtIn && !id.startsWith('${pack.id}:')) {
        throw FormatException('$path: "$id" must start with "${pack.id}:"');
      }
    }

    final entities = <Entity>[];
    final sources = <String, Source>{};
    final generators = <String, Generator>{};
    final prefabs = <Prefab>[];
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (!reads(path)) continue;
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        throw FormatException('$path is not JSON');
      }
      final [folder, file] = path.split('/');
      final name = file.substring(0, file.length - '.json'.length);
      switch (folder) {
        case 'entities':
          final entity = Entity.fromJson(json);
          if (entity == null) throw FormatException('$path needs an "id"');
          own(path, entity.id);
          entities.add(entity);
        case 'sources':
          sources[name] =
              Source.fromJson(json) ??
              (throw FormatException(
                '$path needs a "url" starting http://, https:// or os://',
              ));
        case 'generators':
          final generator = Generator.fromJson(json);
          if (generator == null) {
            throw FormatException('$path needs "from" and "entity"');
          }
          switch (generator.entity['id']) {
            case final String id:
              own(path, id);
            default:
              throw FormatException('$path: "entity" needs an "id"');
          }
          generators[name] = generator;
        case 'prefabs':
          final prefab = Prefab.fromJson(json);
          if (prefab == null) {
            throw FormatException('$path needs an "id" and a "root"');
          }
          own(path, prefab.id);
          prefabs.add(prefab);
      }
    }
    for (final entity in [
      ...entities,
      for (final generator in generators.values)
        ?Entity.fromJson(generator.entity),
    ]) {
      if (entity.feed case final feed?
          when !feed.isAddress && feed.name != null) {
        if (!sources.containsKey(feed.name)) {
          throw FormatException(
            '"${entity.id}" is fed by "${feed.name}", which is not in sources/',
          );
        }
      }
    }
    for (final MapEntry(key: name, value: generator) in generators.entries) {
      if (!sources.containsKey(generator.from)) {
        throw FormatException(
          'generators/$name.json reads "${generator.from}", which is not in '
          'sources/',
        );
      }
    }
    return PackContents(
      pack,
      entities: entities,
      sources: sources,
      generators: generators,
      prefabs: prefabs,
    );
  }
}

/// What every installed pack holds; packs that cannot be read are left out.
final packContentsProvider = FutureProvider<List<PackContents>>((ref) async {
  final packs = await ref.watch(packsProvider.future);
  final read = ref.watch(packReaderProvider);
  return [for (final pack in packs) ?await _contentsOf(pack, read)];
});

Future<PackContents?> _contentsOf(Pack pack, PackReader read) async {
  final files = <String, String>{};
  for (final path in pack.files.where(PackContents.reads)) {
    final bytes = await read(pack, path);
    if (bytes != null) files[path] = utf8.decode(bytes, allowMalformed: true);
  }
  try {
    return PackContents.parse(pack, files);
  } on FormatException {
    return null;
  }
}
