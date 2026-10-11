import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:path/path.dart' as p;

String _iconUrl(String id, String source) =>
    '/api/icon?id=${Uri.encodeQueryComponent(id)}'
    // The source changes whenever the image does, so it doubles as a cache
    // key.
    '&v=${source.hashCode.toRadixString(36)}';

/// What the config page shows and edits, as JSON: the wallpaper, every entity
/// there is (placed or not), the layout, and what there is to choose from.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final entities = await ref.watch(entitiesProvider.future);
  final config = await ref.watch(configProvider.future);
  final providers = await ref.watch(widgetProvidersProvider.future);
  // Not waited for: the page is worth showing before this is known.
  final playing = ref.watch(nowPlayingProvider).value;
  final wallpapers = [
    for (final path in config.wallpapers)
      if (Wallpaper.fromPath(path) case final wallpaper?)
        {
          'id': WallpaperStore.idOf(path),
          'kind': wallpaper.kind.name,
          // A file never changes under its name, so this caches for good.
          'url':
              '/api/wallpaper?id='
              '${Uri.encodeQueryComponent(WallpaperStore.idOf(path))}',
        },
  ];
  return {
    'wallpapers': wallpapers,
    // Minutes each one stays, or 0 to stay on the first.
    'wallpaperEvery': config.wallpaperEvery,
    'entities': [
      for (final entity in entities)
        {
          'id': entity.id,
          'kind': entity.kind,
          // What can be done with it, by the names actions go by.
          'actions': [
            for (final action in [
              ...?entityKind(entity.kind)?.actions,
              ...entityActions,
            ])
              action.name,
          ],
          'label': entity.label,
          // What the device calls it; ids in the layout are made from it.
          'sourceLabel': entity.sourceLabel,
          // Whether the user chose the name, rather than the device.
          'renamed': config.names.containsKey(entity.id),
          // An uploaded picture, or another entity's.
          'customIcon':
              config.iconOverrides.containsKey(entity.id) ||
              config.iconSources.containsKey(entity.id),
          // The entity whose picture this one shows, if any.
          'iconFrom': config.iconSources[entity.id],
          'wide': entity.wideIcon,
          // Line art, drawn straight on the wallpaper with no entity behind.
          'bare': entity.iconPath == null && entity.svg != null,
          'icon': switch (entity.iconPath ?? entity.svg) {
            null => null,
            final source => _iconUrl(entity.id, source),
          },
        },
    ],
    // Exactly what the TV arranges: entities placed nowhere are already in
    // their section, and entities that are gone are left out.
    'layout': layoutWith(config.layout, entities).toJson(),
    // Pictures the user gave to entities that open a popup, by panel id.
    'panelIcons': {
      for (final panel in config.layout.panels)
        if (config.iconOverrides[Panel.iconKey(panel.id)] case final path?)
          panel.id: _iconUrl(Panel.iconKey(panel.id), path),
    },
    'widgets': [
      for (final kind in WidgetKind.values)
        // App widgets are only offered where there are some.
        if (kind != WidgetKind.android || providers.isNotEmpty)
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
    // Every setting that is plain data, as it is saved; set the same way
    // with `PUT /api/config`.
    'config': config.open,
    // Toasts and the now-playing widget stay empty without it.
    'notificationAccess': await ref.watch(notificationAccessProvider.future),
    // Whether the remote's Home button opens the launcher, and whether
    // the launcher may switch that itself.
    'homeButton': {
      'enabled': await ref.watch(homeButtonEnabledProvider.future),
      'canManage': await ref.watch(canManageHomeButtonProvider.future),
    },
    // What the now-playing widget shows, or null.
    'nowPlaying': playing == null
        ? null
        : {
            'package': playing.packageName,
            'app': playing.appLabel,
            'title': playing.title,
            'artist': playing.artist,
            'playing': playing.playing,
            // A cover never changes under its name, so this caches for good.
            'art': switch (playing.artPath) {
              null => null,
              final path =>
                '/api/media/art?id=${Uri.encodeQueryComponent(p.basename(path))}',
            },
          },
  };
});
