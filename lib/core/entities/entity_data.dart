import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/entities/entity_kinds.dart';

/// What the entity [id] provides now, for whatever shows it: what every
/// entity has (what it is called, its id, its kind) and whatever its kind
/// adds. Kept current: a kind's data watches what it is made from, and so
/// whatever watches this is told when that changes. Null for no such
/// entity.
final entityDataProvider = Provider.autoDispose.family<Object?, String>((
  ref,
  id,
) {
  final entity = ref.watch(
    entitiesProvider.select(
      (entities) =>
          entities.value?.where((entity) => entity.id == id).firstOrNull,
    ),
  );
  if (entity == null) return null;
  final own = entityKind(entity.kind)?.data?.call(ref, entity);
  return switch (own) {
    // All there is of it is one thing, which is then how it reads.
    null => {
      'text': entity.label,
      'id': entity.id,
      'label': entity.label,
      'kind': entity.kind,
    },
    final Map<Object?, Object?> parts => {
      'text': entity.label,
      'id': entity.id,
      'label': entity.label,
      'kind': entity.kind,
      ...parts,
    },
    // What a value of the user's answered, which may be anything.
    _ => own,
  };
});
