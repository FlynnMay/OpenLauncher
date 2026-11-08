import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/icon_sets.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/generator.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/layout_repair.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/sources/source.dart';

/// A pack's entities, sources, generators, prefabs and screens. A pack writes short
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
    this.screens = const {},
    this.start,
    this.inbox,
  });

  static const folders = [
    'entities',
    'sources',
    'generators',
    'prefabs',
    'screens',
  ];

  final Pack pack;
  final List<Entity> entities;

  /// By file name.
  final Map<String, Source> sources;
  final Map<String, Generator> generators;

  final List<Prefab> prefabs;

  /// Screens to start from, by id, in file order.
  final Map<String, Screen> screens;

  /// The screen marked `"start": true`, if any: what the launcher opens on
  /// when this pack's screens are the layout.
  final String? start;

  /// The container named by the [start] screen's `"inbox"`: where new apps
  /// go.
  final String? inbox;

  /// Its screens as a layout opening on [start]; null without one.
  Layout? get starting => switch (start) {
    final start? => Layout(
      screens: [...screens.values],
      inbox: inbox ?? Screen.rootId(start),
      startup: Startup(start),
    ).normalised(),
    null => null,
  };

  /// Whether [path] is one of the files read here.
  static bool reads(String path) =>
      folders.any((folder) => path.startsWith('$folder/'));

  /// Reads [files], JSON text by path, giving the names in them their full
  /// ids. Throws a [FormatException] saying what is wrong.
  static PackContents parse(Pack pack, Map<String, String> files) =>
      _Reading(pack, _decoded(files)).contents();

  static Map<String, Object?> _decoded(Map<String, String> files) {
    final decoded = <String, Object?>{};
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (!reads(path)) continue;
      try {
        decoded[path] = jsonDecode(text);
      } on FormatException {
        throw FormatException('$path is not JSON');
      }
    }
    return decoded;
  }
}

/// A pack's files being read into its [PackContents].
class _Reading {
  _Reading(this.pack, this.decoded)
    : glue = _Glue(pack, {
        for (final MapEntry(key: path, value: json) in decoded.entries)
          if (path.startsWith('entities/'))
            if (json case {'id': final String id}) id,
      });

  final Pack pack;
  final Map<String, Object?> decoded;
  final _Glue glue;

  final entities = <Entity>[];
  final sources = <String, Source>{};
  final generators = <String, Generator>{};
  final prefabs = <Prefab>[];
  final screens = <String, Screen>{};
  String? start, inbox;

  PackContents contents() {
    for (final MapEntry(key: path, value: json) in decoded.entries) {
      _read(path, json);
    }
    _requireNamedPacksListed();
    _requireSourcesOfFeeds();
    _requireSourcesOfGenerators();
    return PackContents(
      pack,
      entities: entities,
      sources: sources,
      generators: generators,
      prefabs: prefabs,
      screens: screens,
      start: start,
      inbox: inbox,
    );
  }

  void _read(String path, Object? json) {
    final [folder, file] = path.split('/');
    final name = file.substring(0, file.length - '.json'.length);
    switch (folder) {
      case 'entities':
        _readEntity(path, json);
      case 'sources':
        sources[name] =
            Source.fromJson(json) ??
            (throw FormatException(
              '$path needs a "url" starting http://, https://, os:// or '
              'launcher://',
            ));
      case 'generators':
        _readGenerator(path, name, json);
      case 'prefabs':
        _readPrefab(path, json);
      case 'screens':
        _readScreen(path, json);
    }
  }

  void _readEntity(String path, Object? json) {
    final entity = Entity.fromJson(glue.defined(path, json));
    if (entity == null) throw FormatException('$path needs an "id"');
    entities.add(entity);
  }

  void _readGenerator(String path, String name, Object? json) {
    final generator = Generator.fromJson(glue.generator(path, json));
    if (generator == null) {
      throw FormatException('$path needs "from" and "entity"');
    }
    generators[name] = generator;
  }

  void _readPrefab(String path, Object? json) {
    final prefab = Prefab.fromJson(glue.defined(path, json));
    if (prefab == null) {
      throw FormatException('$path needs an "id" and a "root"');
    }
    prefabs.add(prefab);
  }

  void _readScreen(String path, Object? json) {
    if (glue.defined(path, json)
        case {'id': final String id} && final Map<Object?, Object?> json) {
      screens[id] = Screen.fromJson(json);
      if (json['start'] == true && start == null) {
        start = id;
        inbox = jsonOptional<String>(json, 'inbox');
      }
    } else {
      throw FormatException('$path needs an "id"');
    }
  }

  void _requireNamedPacksListed() {
    for (final other in glue.named) {
      if (other != pack.id && !pack.requires.contains(other)) {
        throw FormatException(
          'It names the pack "$other", which pack.json does not require',
        );
      }
    }
  }

  void _requireSourcesOfFeeds() {
    final generated = generators.values.map(
      (generator) => Entity.fromJson(generator.entity),
    );
    for (final entity in [...entities, ...generated.nonNulls]) {
      if (entity.feed case final feed?
          when !feed.isAddress && feed.name != null) {
        if (!sources.containsKey(feed.name)) {
          throw FormatException(
            '"${entity.id}" is fed by "${feed.name}", which is not in sources/',
          );
        }
      }
    }
  }

  void _requireSourcesOfGenerators() {
    for (final MapEntry(key: name, value: generator) in generators.entries) {
      if (!sources.containsKey(generator.from)) {
        throw FormatException(
          'generators/$name.json reads "${generator.from}", which is not in '
          'sources/',
        );
      }
    }
  }
}

/// What the installed packs call entity categories, in their order.
final categoriesProvider = Provider<Map<String, String>>(
  (ref) => Pack.categoriesOf(ref.watch(packsProvider).value ?? const []),
);

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
          (slot) => '{{${_withUnquotedRootsInFull(slot[1]!)}}}',
        );

  String _withUnquotedRootsInFull(String path) => path.replaceAllMapped(
    _unquoted,
    (part) => part[1] != null ? part[0]! : _withRootsInFull(part[0]!),
  );

  String _withRootsInFull(String text) => text.replaceAllMapped(_root, (root) {
    final name = root[2]!;
    return entities.contains(name) ? '${root[1]}${pack.id}:$name' : root[0]!;
  });

  static final _unquoted = RegExp('(\'[^\']*\'|"[^"]*")|[^\'"]+');

  /// A name where a value's path starts: at the start, or after a space,
  /// bracket or comparison, and before a step, space, pipe or the end.
  static final _root = RegExp(r'(^|[\s(!=<>?:])([A-Za-z][\w-]*)(?=[.\s|\[]|$)');

  /// [json] with its prefabs (named as instances, cards, templates or in
  /// rules), entity variables, act entities and template roots in full.
  Object? _tree(Object? json) => switch (json) {
    final String text => _text(text),
    final List<Object?> list => [for (final item in list) _tree(item)],
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String)
          key: switch ((key, value)) {
            ('prefab' || 'card' || 'template', final String prefab) => _ref(
              prefab,
            ),
            ('variables', final Map<Object?, Object?> vars) => _variablesInFull(
              vars,
            ),
            ('entity', final String entity) => _ref(entity),
            ('prefabRules', final Map<Object?, Object?> rules) => _rulesInFull(
              rules,
            ),
            _ => _tree(value),
          },
    },
    _ => json,
  };

  Map<String, Object?> _rulesInFull(Map<Object?, Object?> rules) => {
    for (final MapEntry(:key, :value) in rules.entries)
      if (key is String) _ref(key): _tree(value),
  };

  Map<String, Object?> _variablesInFull(Map<Object?, Object?> variables) => {
    for (final MapEntry(key: name, value: variable) in variables.entries)
      '$name': switch (variable) {
        {'type': 'entity', 'value': final String id} => {
          ..._tree(variable) as Map<String, Object?>,
          'value': _ref(id),
        },
        _ => _tree(variable),
      },
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

  /// An entity, prefab or layout: [json] with its own id given in full.
  Object? defined(String path, Object? json) => switch (json) {
    {'id': final Object? id} && final Map<Object?, Object?> json => {
      ...?_tree({...json}..remove('id')) as Map<String, Object?>?,
      'id': _id(path, id),
    },
    _ => json,
  };
}
