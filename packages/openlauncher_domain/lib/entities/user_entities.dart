import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/layout/layout_ids.dart';

/// The most entities a user can make.
const maxUserEntities = 24;

/// Ids an entity the user makes may not take: what an action's templates
/// read itself as.
const reservedIds = {'self'};

/// The user's own entities from a save. Skips what cannot be read, duplicate
/// ids, ids that are not plain slugs and [reservedIds].
List<Entity> userEntitiesFromJson(Object? json) {
  final used = {...reservedIds};
  return [
    if (json is List)
      for (final one in json.take(maxUserEntities))
        if (Entity.fromJson(one) case final entity?
            when entity.id == slugOf(entity.id, '') && used.add(entity.id))
          entity,
  ];
}
