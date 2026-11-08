import 'package:meta/meta.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/json/shallow_equality.dart';
import 'package:openlauncher_domain/values/template.dart';

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
  /// id is the one. `{{settings...}}` reads [settings], the pack's plain
  /// values, so a pack can have the user's prefix in its ids or labels.
  List<Entity> entitiesFrom(
    List<Object?> rows, {
    Map<String, Object?> settings = const {},
  }) {
    final made = <String, Entity>{};
    for (final row in rows) {
      if (made.length == maxEntities) break;
      Object? lookup(String root) => switch (root) {
        'row' => row,
        'settings' => settings,
        _ => null,
      };
      if (where case final where?
          when !isTruthy(Template.parse(where).evaluate(lookup))) {
        continue;
      }
      final json = filled(entity, lookup, const {
        'row',
        'settings',
      }) as Map<String, Object?>;
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
      mapsEqual(other.entity, entity);

  @override
  int get hashCode => Object.hash(from, where);
}

/// [json] with the slots of its text that read only [roots] filled.
Object? filled(
  Object? json,
  Object? Function(String root) lookup, [
  Set<String> roots = const {'row'},
]) => switch (json) {
  final String text when text.contains('{{') => Template.parse(
    text,
  ).fill(roots, lookup),
  final Map<Object?, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      if (key is String) key: filled(value, lookup, roots),
  },
  final List<Object?> list => [
    for (final item in list) filled(item, lookup, roots),
  ],
  _ => json,
};
