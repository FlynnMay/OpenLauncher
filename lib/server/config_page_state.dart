import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:path/path.dart' as p;

String _iconUrl(String id, String source) =>
    '/api/icon?id=${Uri.encodeQueryComponent(id)}'
    // The source's hash is the cache key.
    '&v=${source.hashCode.toRadixString(36)}';

/// The state the editor loads: entities, layout, config and choices.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  final providers = await ref.watch(widgetProvidersProvider.future);
  // Not awaited; the page should not wait for it.
  final playing = ref.watch(nowPlayingProvider).value;
  return {
    'entities': [
      for (final entity in entities)
        {
          // As it is: its actions, feed and prefab with it.
          ...entity.toJson(),
          'name': entity.name,
          // The icon is sent as a URL.
          'data': {
            ...entity.data,
            if (entity.data[Entity.icon] case final String source)
              Entity.icon: _iconUrl(entity.id, source),
          },
        },
    ],
    // As the TV draws it: unplaced entities in the inbox, missing ones
    // dropped.
    'layout': layoutWith(config.layout, entities).toJson(),
    'components': [
      for (final kind in ComponentRegistry.values)
        // App widgets only where some exist.
        if (kind != ComponentRegistry.android || providers.isNotEmpty)
          {
            'type': kind.name,
            'label': kind.label,
            'w': kind.defaultW,
            'h': kind.defaultH,
          },
    ],
    'widgetProviders': [
      for (final provider in providers)
        {'id': provider.id, 'label': provider.label, 'app': provider.appLabel},
    ],
    // Everything but the layout, files by id (served at `/api/media/<id>`);
    // set with `PUT /api/config`.
    'config': MediaStore.withIds(config.open),
    // Their files are served at `/api/packs/<id>/<path>`.
    'packs': [
      for (final pack in await ref.watch(packsProvider.future)) pack.toJson(),
    ],
    'update': ref.watch(updateStateProvider).toJson(),
    // What the user has allowed the launcher in the TV's settings.
    'access': {
      for (final access in Access.values)
        access.name: await ref.watch(accessProvider(access).future),
    },
    'nowPlaying': playing == null
        ? null
        : {
            'package': playing.packageName,
            'app': playing.appLabel,
            'title': playing.title,
            'artist': playing.artist,
            'playing': playing.playing,
            // Immutable URL.
            'art': switch (playing.artPath) {
              null => null,
              final path =>
                '/api/playing/art?id=${Uri.encodeQueryComponent(p.basename(path))}',
            },
          },
  };
});
