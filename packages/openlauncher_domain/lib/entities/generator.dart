import 'package:meta/meta.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/json/shallow_equality.dart';
import 'package:openlauncher_domain/values/template.dart';
import 'package:openlauncher_domain/values/template_fill.dart';

/// Turns a source's rows into entities, from a pack's
/// `generators/<name>.json`: `{from, where, tables, entity}`. `entity` is
/// Entity JSON whose `{{row...}}` slots are filled from each row; other slots
/// (`self`, args) are left for when an action runs. `tables` are lookups the
/// slots read as `{{get(tables.sky, row.code)}}`.
@immutable
class Generator {
  const Generator({
    required this.from,
    required this.entity,
    this.where,
    this.tables = const {},
  });

  static const maxEntities = 500;

  /// A source of the same pack, by name.
  final String from;

  /// Rows it does not hold for are skipped.
  final String? where;

  final Map<String, Object?> entity;

  /// Table name -> key -> value.
  final Map<String, Object?> tables;

  static Generator? fromJson(Object? json) => switch (json) {
    {'from': final String from, 'entity': final Map<Object?, Object?> entity}
        when from.isNotEmpty =>
      Generator(
        from: from,
        where: switch (json['where']) {
          final String where when where.trim().isNotEmpty => where,
          _ => null,
        },
        entity: {
          for (final MapEntry(:key, :value) in entity.entries)
            if (key is String) key: value,
        },
        tables: switch (json['tables']) {
          final Map<Object?, Object?> tables => {
            for (final MapEntry(:key, :value) in tables.entries)
              if (key is String) key: value,
          },
          _ => const {},
        },
      ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'from': from,
    'where': ?where,
    if (tables.isNotEmpty) 'tables': tables,
    'entity': entity,
  };

  /// Whether the entities it makes are called [id]: its entity's id has no
  /// slot, so it makes just that one.
  bool makes(String id) => entity['id'] == id;

  /// One entity per row it holds for, up to [maxEntities]; the first with an
  /// id is the one. `{{settings...}}` reads [settings], the pack's plain
  /// values, and each name in [params] the value its source was asked with,
  /// so a pack can have the user's prefix in its ids or labels.
  List<Entity> entitiesFrom(
    List<Object?> rows, {
    Map<String, Object?> settings = const {},
    Map<String, Object?> params = const {},
  }) {
    final made = <String, Entity>{};
    for (final row in rows) {
      if (made.length == maxEntities) break;
      Object? lookup(String root) => switch (root) {
        'row' => row,
        'settings' => settings,
        'tables' => tables,
        _ => params[root],
      };
      if (where case final where?
          when !isTruthy(Template.parse(where).evaluate(lookup))) {
        continue;
      }
      final json = fillSlots(entity, {
        'row',
        'settings',
        'tables',
        ...params.keys,
      }, lookup) as Map<String, Object?>;
      // A value with nothing to say is left out.
      if (json['data'] case final Map<String, Object?> data) {
        data.removeWhere((_, value) => value == null);
      }
      if (Entity.fromJson(json) case final entity?) {
        made.putIfAbsent(entity.id, () => entity);
      }
    }
    return [...made.values];
  }

  @override
  bool operator ==(Object other) =>
      other is Generator &&
      other.from == from &&
      other.where == where &&
      mapsEqual(other.entity, entity) &&
      mapsEqual(other.tables, tables);

  @override
  int get hashCode => Object.hash(from, where);
}
