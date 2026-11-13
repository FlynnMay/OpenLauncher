/// Chunks of JSON written once and used by name. Deliberately not in any
/// barrel.
///
/// - `"$defs": { "name": chunk }` on any object defines chunks for everything
///   inside that object.
/// - `{ "$use": "name", "params": {...}, ...other keys }` is the chunk, with
///   its `{{param.x}}` filled and the other keys written over it as a JSON
///   Merge Patch: objects merge, `null` removes a key, anything else replaces.
/// - A chunk that takes parameters declares them, with their defaults, as
///   `"$params": {...}` in its body.
/// - `{ "$spread": "name" }` in a list puts the items of a list chunk there.
/// - `$schema` and `$comment` are dropped.
///
/// Only `{{param...}}` is filled here; every other slot is left for the
/// place that reads it.
library;

import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/values/template_fill.dart';

/// A set of chunks and where they were written, for error messages.
class DefsLevel {
  const DefsLevel(this.label, this.defs);

  final String label;
  final Json defs;
}

/// Why a file's chunks could not be put together.
class JsonExpandError extends FormatException {
  JsonExpandError(String reason, {String? source, String at = ''})
    : super([?source, if (at.isNotEmpty) at, reason].join(': '));
}

/// The chunks in a `defs` file: the `$defs` it holds.
DefsLevel defsLevelOf(Object? json, String source) => switch (json) {
  {r'$defs': final Map<Object?, Object?> defs} => DefsLevel(
    source,
    jsonStringKeyed(defs),
  ),
  final Map<Object?, Object?> map when !map.containsKey(r'$defs') => DefsLevel(
    source,
    const {},
  ),
  _ => throw JsonExpandError(r'"$defs" must be an object', source: source),
};

/// [json] with its chunks put together. [levels] are the chunks it can use
/// from outside itself, nearest first.
Object? expandJson(
  Object? json, {
  List<DefsLevel> levels = const [],
  String? source,
}) => _Expander(source).expand(json, levels);

/// [json] with `{{param.x}}` read from [values]; other slots are left as
/// written, and a lone slot keeps its value's type.
Object? fillParameters(Object? json, Map<String, Object?> values) =>
    fillSlots(json, const {'param'}, (root) => root == 'param' ? values : null);

/// [base] with [over] written on it as a JSON Merge Patch (RFC 7396).
Object? jsonMergePatch(Object? base, Object? over) {
  if (over is! Map<Object?, Object?>) return over;
  final merged = <Object?, Object?>{if (base is Map<Object?, Object?>) ...base};
  for (final MapEntry(:key, :value) in over.entries) {
    if (value == null) {
      merged.remove(key);
    } else {
      merged[key] = jsonMergePatch(merged[key], value);
    }
  }
  return merged;
}

const _use = r'$use';
const _spread = r'$spread';
const _defs = r'$defs';
const _params = r'$params';
const _dropped = {r'$schema', r'$comment'};

/// Past this many values a file is refused: chunks that use chunks can grow
/// without end, and a pack is someone else's file.
const _maxValues = 200000;

class _Expander {
  _Expander(this.source);

  final String? source;
  final _path = <String>[];
  final _active = <Object>[];
  var _values = 0;

  JsonExpandError _fail(String reason) =>
      JsonExpandError(reason, source: source, at: _at);

  String get _at => _path.isEmpty ? '' : '/${_path.join('/')}';

  Object? expand(Object? node, List<DefsLevel> levels) {
    if (++_values > _maxValues) {
      throw _fail(
        'It grows past $_maxValues values; a chunk is probably using itself '
        'many times',
      );
    }
    return switch (node) {
      final List<Object?> list => _list(list, levels),
      final Map<Object?, Object?> map => _object(jsonStringKeyed(map), levels),
      _ => node,
    };
  }

  List<Object?> _list(List<Object?> list, List<DefsLevel> levels) => [
    for (final (index, item) in list.indexed) ..._item(index, item, levels),
  ];

  List<Object?> _item(int index, Object? item, List<DefsLevel> levels) {
    _path.add('$index');
    try {
      return switch (item) {
        final Map<Object?, Object?> map when map.containsKey(_spread) =>
          _spreading(jsonStringKeyed(map), levels),
        _ => [expand(item, levels)],
      };
    } finally {
      _path.removeLast();
    }
  }

  Object? _object(Json map, List<DefsLevel> levels) {
    if (map.containsKey(_spread)) {
      throw _fail(r'$spread belongs on its own as an item of a list');
    }
    if (map.containsKey(_params)) {
      throw _fail(r'$params belongs in the body of an entry of $defs');
    }
    final here = _withOwnDefs(map, levels);
    final using = map.containsKey(_use);
    final over = <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries)
        if (!_dropped.contains(key) &&
            key != _defs &&
            key != _use &&
            !(using && key == 'params'))
          key: _child(key, value, here),
    };
    return using ? jsonMergePatch(_chunk(map, here), over) : over;
  }

  Object? _child(String key, Object? value, List<DefsLevel> levels) {
    _path.add(key);
    try {
      return expand(value, levels);
    } finally {
      _path.removeLast();
    }
  }

  List<DefsLevel> _withOwnDefs(Json map, List<DefsLevel> levels) =>
      switch (map[_defs]) {
        null => levels,
        final Map<Object?, Object?> defs => [
          DefsLevel(source ?? 'this file', jsonStringKeyed(defs)),
          ...levels,
        ],
        _ => throw _fail(r'"$defs" must be an object'),
      };

  /// What the chunk `$use` names comes to, before anything is written over it.
  Object? _chunk(Json map, List<DefsLevel> levels) {
    final found = _find(map[_use], levels);
    final def = found.def;
    if (def is! Map<Object?, Object?>) {
      throw _fail(
        '"${found.name}" is a list; put it in a list with '
        '{"\$spread": "${found.name}"}',
      );
    }
    final body = jsonStringKeyed(def);
    final declared = body.remove(_params);
    final values = _parameters(found.name, declared, map['params'], levels);
    return _inside(
      def,
      () => expand(fillParameters(body, values), found.inside),
    );
  }

  Map<String, Object?> _parameters(
    String name,
    Object? declared,
    Object? given,
    List<DefsLevel> levels,
  ) {
    final defaults = switch (declared) {
      null => const <String, Object?>{},
      final Map<Object?, Object?> map => jsonStringKeyed(map),
      _ => throw _fail('"$name" has $_params that is not an object'),
    };
    final written = switch (given) {
      null => const <String, Object?>{},
      final Map<Object?, Object?> map => jsonStringKeyed(
        _child('params', map, levels) as Map,
      ),
      _ => throw _fail('"params" must be an object'),
    };
    final unknown = written.keys.where((key) => !defaults.containsKey(key));
    if (unknown.isNotEmpty) {
      throw _fail('"$name" has no parameter "${unknown.first}"');
    }
    return {...defaults, ...written};
  }

  /// The items a `$spread` stands for.
  List<Object?> _spreading(Json map, List<DefsLevel> levels) {
    final stray = map.keys.where((key) => key != _spread);
    if (stray.isNotEmpty) {
      throw _fail(
        r'$spread takes no other key, but has "'
        '${stray.first}"',
      );
    }
    final found = _find(map[_spread], levels);
    final def = found.def;
    if (def is! List<Object?>) {
      throw _fail('"${found.name}" is not a list, so it cannot be spread');
    }
    return _inside(def, () => _list(def, found.inside));
  }

  T _inside<T>(Object def, T Function() run) {
    if (_active.any((going) => identical(going, def))) {
      throw _fail('Chunks use each other in a circle');
    }
    _active.add(def);
    try {
      return run();
    } finally {
      _active.removeLast();
    }
  }

  ({String name, Object? def, List<DefsLevel> inside}) _find(
    Object? name,
    List<DefsLevel> levels,
  ) {
    if (name is! String) throw _fail('The name of a chunk must be text');
    for (final (index, level) in levels.indexed) {
      if (level.defs.containsKey(name)) {
        return (
          name: name,
          def: level.defs[name],
          inside: levels.sublist(index),
        );
      }
    }
    throw _fail('"$name" is not defined here, in its type or in the pack');
  }
}
