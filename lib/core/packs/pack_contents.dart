import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/packs/icon_sets.dart';
import 'package:openlauncher/core/packs/pack.dart';
import 'package:openlauncher/core/packs/pack_layout.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/generator.dart';
import 'package:openlauncher_domain/json/json_decode.dart';
import 'package:openlauncher_domain/json/json_expand.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/json/json_walk.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/layout_repair.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/nodes/node_names.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/sources/source.dart';
import 'package:openlauncher_domain/values/template.dart';
import 'package:openlauncher_domain/variables/variable.dart';

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

  /// Whether [path] is one of the files read here. Files of the old layout
  /// are, so that [parse] can say so.
  static bool reads(String path) =>
      PackFile.isPackDefs(path) ||
      PackFile.defsFeatureOf(path) != null ||
      PackFile.of(path) != null ||
      PackFile.isOld(path);

  /// Reads [files], JSON text by path, giving the names in them their full
  /// ids. Throws a [FormatException] saying what is wrong.
  static PackContents parse(Pack pack, Map<String, String> files) {
    final old = files.keys.where(PackFile.isOld).firstOrNull;
    if (old != null) {
      throw FormatException(
        '$old is in the old pack layout: a pack has a folder for each '
        'feature, holding files like source.jsonc or prefab.jsonc',
      );
    }
    return _Reading(pack, _decoded(files)).contents();
  }

  static Map<String, Object?> _decoded(Map<String, String> files) {
    final pack = <DefsLevel>[];
    final features = <String, DefsLevel>{};
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (PackFile.isPackDefs(path)) {
        pack.add(defsLevelOf(decodeJson(text, source: path), path));
      } else if (PackFile.defsFeatureOf(path) case final feature?) {
        features[feature] = defsLevelOf(decodeJson(text, source: path), path);
      }
    }
    final decoded = <String, Object?>{};
    for (final MapEntry(key: path, value: text) in files.entries) {
      final file = PackFile.of(path);
      if (file == null) continue;
      final json = decodeJson(text, source: path);
      decoded[path] = file.kind == PackKind.field
          ? json
          : expandJson(
              json,
              levels: [?features[file.feature], ...pack],
              source: path,
            );
    }
    return decoded;
  }
}

/// A pack's files being read into its [PackContents].
class _Reading {
  _Reading(this.pack, Map<String, Object?> decoded)
    : items = [
        for (final MapEntry(key: path, value: json) in decoded.entries)
          for (final item in PackFile.of(path)!.items(path, json))
            (PackFile.of(path)!.kind, item),
      ] {
    glue = _Glue(
      pack,
      {
        for (final (kind, item) in items)
          if (kind == PackKind.entity)
            if (item.json['id'] case final String id) id,
      },
      {
        for (final (kind, item) in items)
          if (kind == PackKind.field) item.name,
      },
    );
  }

  final Pack pack;
  final List<(PackKind, PackItem)> items;
  late final _Glue glue;

  final entities = <Entity>[];
  final sources = <String, Source>{};
  final generators = <String, Generator>{};
  final prefabs = <Prefab>[];
  final screens = <String, Screen>{};
  String? start, inbox;

  PackContents contents() {
    for (final (kind, item) in items) {
      _read(kind, item);
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

  Source _readSource(PackItem item) {
    final source =
        Source.fromJson(glue.source(item.json)) ??
        (throw FormatException(
          '${item.where} needs a "url" starting http://, https://, os:// or '
          'launcher://, and a method of GET or POST',
        ));
    final reserved = source.variables.keys.where(
      Source.reservedVariables.contains,
    );
    if (reserved.isNotEmpty) {
      throw FormatException(
        '${item.where} has a variable "${reserved.first}", a name the '
        'launcher reads itself',
      );
    }
    if (source.auth case final profile? when !pack.auth.containsKey(profile)) {
      throw FormatException(
        '${item.where} names auth "$profile", not in pack.json',
      );
    }
    return source.inPack(pack.id);
  }

  void _read(PackKind kind, PackItem item) {
    switch (kind) {
      case PackKind.entity:
        _readEntity(item);
      case PackKind.source:
        _named(sources, item, _readSource(item));
      case PackKind.generator:
        _named(generators, item, _readGenerator(item));
      case PackKind.prefab:
        _readPrefab(item);
      case PackKind.screen:
        _readScreen(item);
      // Premade fields are read with the pack's settings, not here.
      case PackKind.field:
        break;
    }
  }

  void _named<T>(Map<String, T> into, PackItem item, T made) {
    if (into.containsKey(item.name)) {
      throw FormatException('${item.where} is a second "${item.name}"');
    }
    into[item.name] = made;
  }

  void _readEntity(PackItem item) {
    final entity = Entity.fromJson(glue.defined(item.where, item.json));
    if (entity == null) throw FormatException('${item.where} needs an "id"');
    entities.add(entity);
  }

  Generator _readGenerator(PackItem item) =>
      Generator.fromJson(
        glue.generator(
          item.where,
          item.json,
          variables: _variablesOfSource(item.json['from']),
        ),
      ) ??
      (throw FormatException('${item.where} needs "from" and "entity"'));

  /// The names the source called [name] takes, which its generator reads.
  Set<String> _variablesOfSource(Object? name) => {
    for (final (kind, item) in items)
      if (kind == PackKind.source && item.name == name)
        if (item.json['variables'] case final Map<Object?, Object?> variables)
          for (final key in variables.keys) '$key',
  };

  void _readPrefab(PackItem item) {
    final prefab = Prefab.fromJson(glue.defined(item.where, item.json));
    if (prefab == null) {
      throw FormatException('${item.where} needs an "id" and a "root"');
    }
    prefabs.add(prefab);
  }

  void _readScreen(PackItem item) {
    if (glue.defined(item.where, item.json)
        case {'id': final String id} && final Map<Object?, Object?> json) {
      screens[id] = Screen.fromJson(json);
      if (json['start'] == true && start == null) {
        start = id;
        inbox = jsonOptional<String>(json, 'inbox');
      }
    } else {
      throw FormatException('${item.where} needs an "id"');
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
            '"${entity.id}" is fed by "${feed.name}", which is not a source of '
            'this pack',
          );
        }
      }
    }
  }

  void _requireSourcesOfGenerators() {
    for (final MapEntry(key: name, value: generator) in generators.entries) {
      if (!sources.containsKey(generator.from)) {
        throw FormatException(
          'The generator "$name" reads "${generator.from}", which is not a '
          'source of this pack',
        );
      }
    }
  }
}

/// What the installed packs call entity categories, in their order.
final categoriesProvider = Provider<Map<String, String>>(
  (ref) => Pack.categoriesOf(ref.watch(packsProvider).value ?? const []),
);

/// What each installed pack holds, or why it cannot be read, by pack id.
final packReadingsProvider = FutureProvider<Map<String, PackReading>>((
  ref,
) async {
  final packs = await ref.watch(packsProvider.future);
  final read = ref.watch(packReaderProvider);
  return {for (final pack in packs) pack.id: await _readingOf(pack, read)};
});

/// What every installed pack holds; packs that cannot be read are left out.
final packContentsProvider = FutureProvider<List<PackContents>>((ref) async {
  final readings = await ref.watch(packReadingsProvider.future);
  return [for (final reading in readings.values) ?reading.contents];
});

/// Why each pack that cannot be read cannot, by pack id.
final packLoadErrorsProvider = FutureProvider<Map<String, String>>((ref) async {
  final readings = await ref.watch(packReadingsProvider.future);
  return {
    for (final MapEntry(:key, :value) in readings.entries) key: ?value.error,
  };
});

/// A pack's contents, or the reason they could not be read.
typedef PackReading = ({PackContents? contents, String? error});

Future<PackReading> _readingOf(Pack pack, PackReader read) async {
  final files = <String, String>{};
  for (final path in pack.files.where(PackContents.reads)) {
    final bytes = await read(pack, path);
    if (bytes != null) files[path] = utf8.decode(bytes, allowMalformed: true);
  }
  try {
    return (contents: PackContents.parse(pack, files), error: null);
  } on FormatException catch (error) {
    return (contents: null, error: error.message);
  }
}

/// Gives the names a pack writes their full ids. The ids it defines are its
/// own; a name it refers to is its own too unless it says another pack's.
/// Template roots are its own only where they name one of its entities.
class _Glue {
  _Glue(this.pack, this.entities, this.fields);

  final Pack pack;

  /// Names of the premade fields it defines in `fields/`.
  final Set<String> fields;

  /// Short ids of the entities it defines in `entities/`.
  final Set<String> entities;

  /// The other packs it names.
  final named = <String>{};

  static final _slot = RegExp(r'\{\{(.*?)\}\}');

  String _id(String path, Object? short) => switch (short) {
    final String short when isNodeId(short) => '${pack.id}:$short',
    _ => throw FormatException(
      '$path: "$short" must be letters, digits, "_" and "-"',
    ),
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
  String _text(String text) => !isTemplate(text)
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
    return entities.contains(name) &&
            !_readByGenerators.contains(name) &&
            !_variablesOfGenerator.contains(name)
        ? '${root[1]}${pack.id}:$name'
        : root[0]!;
  });

  /// What a generator's slots read besides entities: an entity of the same
  /// name is still reached as `pack:name`.
  static const _readByGenerators = {'row', 'settings', 'tables'};

  /// The variables of the source the generator being read reads, whose names
  /// are not entities either.
  Set<String> _variablesOfGenerator = const {};

  static final _unquoted = RegExp('(\'[^\']*\'|"[^"]*")|[^\'"]+');

  /// A name where a value's path starts: at the start, or after a space,
  /// bracket or comparison, and before a step, space, pipe or the end.
  static final _root = RegExp(
    r'(^|[\s(!=<>?:])([A-Za-z][\w-]*)(?=[.\s|\[/#]|$)',
  );

  /// [json] with its prefabs (named as instances, cards, templates or in
  /// rules), entity variables, act entities and template roots in full.
  Object? _tree(Object? json) => walkJson(
    json,
    onText: _text,
    onEntry: (key, value, walk) => switch ((key, value)) {
      ('prefab' || 'card' || 'template', final String prefab) => _ref(prefab),
      ('variables', final Map<Object?, Object?> vars) => _variablesInFull(vars),
      ('entity', final String entity) => _ref(entity),
      ('prefabRules', final Map<Object?, Object?> rules) => _rulesInFull(rules),
      _ => walk(value),
    },
  );

  Map<String, Object?> _rulesInFull(Map<Object?, Object?> rules) => {
    for (final MapEntry(:key, :value) in rules.entries)
      if (key is String) _ref(key): _tree(value),
  };

  Map<String, Object?> _variablesInFull(Map<Object?, Object?> variables) => {
    for (final MapEntry(key: name, value: variable) in variables.entries)
      _freeName('$name'): switch (variable) {
        {'type': 'entity', 'value': final String id} => {
          ..._tree(variable) as Map<String, Object?>,
          'value': _ref(id),
        },
        {'type': final String type} when _isPremadeField(type) => {
          ..._tree(variable) as Map<String, Object?>,
          'type': _ref(type),
        },
        _ => _tree(variable),
      },
  };

  String _freeName(String name) => isFreeName(name)
      ? name
      : throw FormatException('"$name" is a word that starts an address');

  /// Whether a variable's `type` names a premade field and not a plain type.
  bool _isPremadeField(String type) {
    if (fields.contains(type) && Variable.typeOf(type).$1 != VarType.field) {
      throw FormatException(
        '"$type" is a reserved name: write "${pack.id}:$type" '
        'for the field of that name',
      );
    }
    return Variable.typeOf(type).$1 == VarType.field;
  }

  /// A source: [json] with the premade fields its variables are given in
  /// full.
  Object? source(Object? json) => switch (json) {
    {'variables': final Map<Object?, Object?> variables} &&
        final Map<Object?, Object?> json =>
      {...json, 'variables': _variablesInFull(variables)},
    _ => json,
  };

  /// A generator's entity id is a template: its own text has no ":". Its
  /// source's [variables] are read as they are.
  Object? generator(
    String path,
    Object? json, {
    Set<String> variables = const {},
  }) {
    _variablesOfGenerator = variables;
    try {
      return _generator(path, json);
    } finally {
      _variablesOfGenerator = const {};
    }
  }

  Object? _generator(String path, Object? json) => switch (json) {
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
