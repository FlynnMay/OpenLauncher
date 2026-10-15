import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/settings/place_search.dart';

/// Built-in values with their current reading, the TV's place, and the user's
/// own entities: what each reads and the actions it defines.
class ValuesSettings extends ConsumerWidget {
  const ValuesSettings({
    super.key,
    required this.entities,
    required this.place,
    required this.onEntities,
    required this.onPlace,
  });

  final List<Entity> entities;
  final Place? place;
  final void Function(List<Entity> entities) onEntities;
  final void Function(Place? place) onPlace;

  /// Most fields listed per value.
  static const _mostParts = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final operations = ref.watch(operationsRegistryProvider).all;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget reading(String path, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SelectableText('{{$path}}', style: small)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valueText(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    return Section('Values', open: false, [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Use a value in any text field as {{name}}; it updates live.',
        ),
      ),
      for (final entity
          in ref.watch(entitiesProvider).value ?? const <Entity>[])
        if (entity.feed != null && entities.byId(entity.id) == null)
          reading(entity.id, ref.watch(valueProvider(entity.id))),
      const SizedBox(height: 12),
      PlaceSearch(
        said: switch (place) {
          null => 'Location and weather need a location.',
          final place => 'Location: ${place.name}',
        },
        onChosen: onPlace,
      ),
      if (place != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onPlace(null),
            child: const Text('Clear location'),
          ),
        ),
      const Divider(height: 24),
      ListField(
        option: userEntityOptions(operations),
        records: [for (final entity in entities) userEntityToForm(entity)],
        onChanged: (told) {
          final taken = {
            ...reservedIds,
            for (final entity in entities) entity.id,
          };
          onEntities([
            for (final one in told)
              // A new one's id is derived from its name.
              userEntityFromForm(
                {
                  'id': () {
                    final id = freeId(slugOf('${one['name']}', 'value'), taken);
                    taken.add(id);
                    return id;
                  }(),
                  ...one,
                },
                operations,
                was: entities.byId('${one['id']}'),
              ),
          ]);
        },
        after: (one) {
          final id = '${one['id']}';
          final entity = entities.byId(id)!;
          final url = '${entity.feed?.inline?['url'] ?? ''}';
          final asked = entity.feed?.inline != null;
          final address = HttpFeed.addressOf(url);
          return [
            if (asked && url.isNotEmpty && address == null)
              Text(
                'Must start with http:// or https://',
                style: small?.copyWith(color: theme.colorScheme.error),
              ),
            ...switch (valuePaths(id, ref.watch(valueProvider(id)))) {
              final parts when parts.values.every((part) => part == null) => [
                reading(id, null),
                if (asked && address != null)
                  Text('No data received yet.', style: small),
              ],
              final parts => [
                for (final MapEntry(key: path, :value) in parts.entries.take(
                  _mostParts,
                ))
                  reading(path, value),
                if (parts.length > _mostParts)
                  Text('and ${parts.length - _mostParts} more', style: small),
              ],
            },
          ];
        },
      ),
    ]);
  }
}
