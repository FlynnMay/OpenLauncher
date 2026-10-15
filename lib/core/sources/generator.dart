import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/values/template.dart';

/// Turns a source's rows into entities, from a pack's
/// `generators/<name>.json`: `{from, where, entity}`. `entity` is Entity JSON
/// whose `{{row...}}` slots are filled from each row; other slots (`self`,
/// args) are left for when an action runs.
@immutable
class Generator {
  const Generator({required this.from, required this.entity, this.where});

  static const maxEntities = 500;

  /// A source of the same pack, by name.
  final String from;

  /// Rows it does not hold for are skipped.
  final String? where;

  final Map<String, Object?> entity;

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
      ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'from': from,
    'where': ?where,
    'entity': entity,
  };

  /// One entity per row it holds for, up to [maxEntities]; the first with an
  /// id is the one.
  List<Entity> entitiesFrom(List<Object?> rows) {
    final made = <String, Entity>{};
    for (final row in rows) {
      if (made.length == maxEntities) break;
      Object? lookup(String root) => root == 'row' ? row : null;
      if (where case final where?
          when !isTruthy(Template.parse(where).evaluate(lookup))) {
        continue;
      }
      final json = filled(entity, lookup) as Map<String, Object?>;
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
      mapEquals(other.entity, entity);

  @override
  int get hashCode => Object.hash(from, where);
}

/// [json] with the `{{row...}}` slots of its text filled.
Object? filled(Object? json, Object? Function(String root) lookup) =>
    switch (json) {
      final String text when text.contains('{{') => Template.parse(
        text,
      ).fill(const {'row'}, lookup),
      final Map<Object?, Object?> map => <String, Object?>{
        for (final MapEntry(:key, :value) in map.entries)
          if (key is String) key: filled(value, lookup),
      },
      final List<Object?> list => [
        for (final item in list) filled(item, lookup),
      ],
      _ => json,
    };
