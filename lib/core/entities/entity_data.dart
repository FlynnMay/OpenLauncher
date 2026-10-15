import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/sources/source_rows.dart';

/// What `{{<id>...}}` reads for an entity: its label, id, category and
/// [Entity.data], with what its feed reads on top. Null if unknown.
final entityDataProvider = Provider.autoDispose.family<Object?, String>((
  ref,
  id,
) {
  final entity = ref.watch(
    entitiesProvider.select((entities) => entities.value?.byId(id)),
  );
  if (entity == null) return null;
  final own = switch (entity.feed?.at(entity.id)) {
    null => null,
    final at => ref.watch(sourceValueProvider(at)).value,
  };
  return switch (own) {
    null => {
      'text': entity.label,
      'id': entity.id,
      'label': entity.label,
      'category': entity.category,
      ...entity.data,
    },
    final Map<Object?, Object?> parts => {
      'text': entity.label,
      'id': entity.id,
      'label': entity.label,
      'category': entity.category,
      ...entity.data,
      ...parts,
    },
    // A user value can be any JSON.
    _ => own,
  };
});
