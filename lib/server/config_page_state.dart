import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:path/path.dart' as p;

String _iconUrl(String id, String source) =>
    '/api/icon?id=${Uri.encodeQueryComponent(id)}'
    // The source's hash is the cache key.
    '&v=${source.hashCode.toRadixString(36)}';

/// The state the editor loads: wallpapers, entities, layout and choices.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  final providers = await ref.watch(widgetProvidersProvider.future);
  // Not awaited; the page should not wait for it.
  final playing = ref.watch(nowPlayingProvider).value;
  final wallpapers = [
    for (final path in config.wallpapers)
      if (Wallpaper.fromPath(path) case final wallpaper?)
        {
          'id': WallpaperStore.idOf(path),
          'kind': wallpaper.kind.name,
          // Immutable URL.
          'url':
              '/api/wallpaper?id='
              '${Uri.encodeQueryComponent(WallpaperStore.idOf(path))}',
        },
  ];
  return {
    'wallpapers': wallpapers,
    'wallpaperEvery': config.wallpaperEvery,
    'entities': [
      for (final entity in entities)
        {
          'id': entity.id,
          'category': entity.category,
          'actions': [
            for (final action
                in entityRegistry(entity.category)?.actions ?? const [])
              action.name,
          ],
          'label': entity.label,
          'name': entity.name,
          'renamed': config.names.containsKey(entity.id),
          // An uploaded or borrowed picture.
          'customIcon':
              config.iconOverrides.containsKey(entity.id) ||
              config.iconSources.containsKey(entity.id),
          'iconFrom': config.iconSources[entity.id],
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
    // Folder pictures by panel id.
    'panelIcons': {
      for (final panel in config.layout.panels)
        if (config.iconOverrides[Panel.iconKey(panel.id)] case final path?)
          panel.id: _iconUrl(Panel.iconKey(panel.id), path),
    },
    'components': [
      for (final kind in ComponentKind.values)
        // App widgets only where some exist.
        if (kind != ComponentKind.android || providers.isNotEmpty)
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
    // Plain-data settings; set with `PUT /api/config`.
    'config': config.open,
    'notificationAccess': await ref.watch(notificationAccessProvider.future),
    'homeButton': {
      'enabled': await ref.watch(homeButtonEnabledProvider.future),
      'canManage': await ref.watch(canManageHomeButtonProvider.future),
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
                '/api/media/art?id=${Uri.encodeQueryComponent(p.basename(path))}',
            },
          },
  };
});
