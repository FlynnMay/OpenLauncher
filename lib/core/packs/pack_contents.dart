import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/packs/icon_sets.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';
import 'package:openlauncher/core/sources/generator.dart';
import 'package:openlauncher/core/sources/source.dart';

/// A pack's entities, sources, generators and prefabs. A pack writes short
/// names; each is its own unless it says another pack's, `other:name`, and
/// is read as `<pack>:<name>`.
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

  /// Reads [files], JSON text by path, giving the names in them their full
  /// ids. Throws a [FormatException] saying what is wrong.
  static PackContents parse(Pack pack, Map<String, String> files) {
    final decoded = <String, Object?>{};
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (!reads(path)) continue;
      try {
        decoded[path] = jsonDecode(text);
      } on FormatException {
        throw FormatException('$path is not JSON');
      }
    }
    final glue = _Glue(pack, {
      for (final MapEntry(key: path, value: json) in decoded.entries)
        if (path.startsWith('entities/'))
          if (json case {'id': final String id}) id,
    });

    final entities = <Entity>[];
    final sources = <String, Source>{};
    final generators = <String, Generator>{};
    final prefabs = <Prefab>[];
    for (final MapEntry(key: path, value: json) in decoded.entries) {
      final [folder, file] = path.split('/');
      final name = file.substring(0, file.length - '.json'.length);
      switch (folder) {
        case 'entities':
          final entity = Entity.fromJson(glue.entity(path, json));
          if (entity == null) throw FormatException('$path needs an "id"');
          entities.add(entity);
        case 'sources':
          sources[name] =
              Source.fromJson(json) ??
              (throw FormatException(
                '$path needs a "url" starting http://, https://, os:// or '
                'launcher://',
              ));
        case 'generators':
          final generator = Generator.fromJson(glue.generator(path, json));
          if (generator == null) {
            throw FormatException('$path needs "from" and "entity"');
          }
          generators[name] = generator;
        case 'prefabs':
          final prefab = Prefab.fromJson(glue.prefab(path, json));
          if (prefab == null) {
            throw FormatException('$path needs an "id" and a "root"');
          }
          prefabs.add(prefab);
      }
    }
    for (final other in glue.named) {
      if (other != pack.id && !pack.requires.contains(other)) {
        throw FormatException(
          'It names the pack "$other", which pack.json does not require',
        );
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

/// Gives the names a pack writes their full ids. The ids it defines are its
/// own; a name it refers to is its own too unless it says another pack's.
/// Template roots are its own only where they name one of its entities.
class _Glue {
  _Glue(this.pack, this.entities);

  final Pack pack;

  /// Short ids of the entities it defines in `entities/`.
  final Set<String> entities;

  /// The other packs it names.
  final named = <String>{};

  static final _slot = RegExp(r'\{\{(.*?)\}\}');

  String _id(String path, Object? short) => switch (short) {
    final String short when short.isNotEmpty && !short.contains(':') =>
      '${pack.id}:$short',
    _ => throw FormatException('$path: "$short" must be a name without ":"'),
  };

  String _ref(String name) {
    if (name.contains('://') || name.contains('{{')) return name;
    final at = name.indexOf(':');
    if (at < 0) return '${pack.id}:$name';
    named.add(name.substring(0, at));
    return name;
  }

  /// [text] with the template roots that name its entities given in full.
  /// Quoted text is left as it is.
  String _text(String text) => !text.contains('{{')
      ? text
      : text.replaceAllMapped(
          _slot,
          (slot) =>
              '{{${slot[1]!.replaceAllMapped(_unquoted, (part) {
                if (part[1] != null) return part[0]!;
                return part[0]!.replaceAllMapped(_root, (root) {
                  final name = root[2]!;
                  return entities.contains(name) ? '${root[1]}${pack.id}:$name' : root[0]!;
                });
              })}}}',
        );

  static final _unquoted = RegExp('(\'[^\']*\'|"[^"]*")|[^\'"]+');

  /// A name where a value's path starts: at the start, or after a space,
  /// bracket or comparison, and before a step, space, pipe or the end.
  static final _root = RegExp(r'(^|[\s(!=<>?:])([A-Za-z][\w-]*)(?=[.\s|\[]|$)');

  /// [json] with its prefabs, entity variables, act entities and template
  /// roots in full.
  Object? _tree(Object? json) => switch (json) {
    final String text => _text(text),
    final List<Object?> list => [for (final item in list) _tree(item)],
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String)
          key: switch ((key, value)) {
            ('prefab', final String prefab) => _ref(prefab),
            ('vars', final Map<Object?, Object?> vars) => {
              for (final MapEntry(key: name, value: variable) in vars.entries)
                '$name': switch (variable) {
                  {'type': 'entity', 'value': final String id} => {
                    ..._tree(variable) as Map<String, Object?>,
                    'value': _ref(id),
                  },
                  _ => _tree(variable),
                },
            },
            ('entity', final String entity) => _ref(entity),
            _ => _tree(value),
          },
    },
    _ => json,
  };

  Object? entity(String path, Object? json) => switch (json) {
    {'id': final Object? id} && final Map<Object?, Object?> json => {
      ...?_tree({...json}..remove('id')) as Map<String, Object?>?,
      'id': _id(path, id),
    },
    _ => json,
  };

  /// A generator's entity id is a template: its own text has no ":".
  Object? generator(String path, Object? json) => switch (json) {
    {'entity': {'id': final String id} && final Map<Object?, Object?> entity} &&
        final Map<Object?, Object?> json =>
      {
        ...json,
        'entity': {
          ..._tree({...entity}..remove('id')) as Map<String, Object?>,
          'id': switch (id.replaceAll(_slot, '')) {
            final literal when literal.contains(':') => throw FormatException(
              '$path: "$id" must be a name without ":"',
            ),
            _ => '${pack.id}:$id',
          },
        },
      },
    _ => json,
  };

  Object? prefab(String path, Object? json) => switch (json) {
    {'id': final Object? id} && final Map<Object?, Object?> json => {
      ...?_tree({...json}..remove('id')) as Map<String, Object?>?,
      'id': _id(path, id),
    },
    _ => json,
  };
}
