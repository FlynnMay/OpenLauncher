import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
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

/// What the config page shows and edits, as JSON: the wallpaper, every card
/// there is (placed or not), the layout, and what there is to choose from.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final cards = await ref.watch(allCardsProvider.future);
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
    'cards': [
      for (final card in cards)
        {
          'id': card.id,
          'kind': card.kind.name,
          'label': card.label,
          // What the device calls it; ids in the layout are made from it.
          'sourceLabel': card.sourceLabel,
          // Whether the user chose the name, rather than the device.
          'renamed': config.names.containsKey(card.id),
          // An uploaded picture, or another card's.
          'customIcon':
              config.iconOverrides.containsKey(card.id) ||
              config.iconSources.containsKey(card.id),
          // The card whose picture this one shows, if any.
          'iconFrom': config.iconSources[card.id],
          'wide': card.wideIcon,
          // Line art, drawn straight on the wallpaper with no card behind.
          'bare': card.iconPath == null && card.svg != null,
          'icon': switch (card.iconPath ?? card.svg) {
            null => null,
            final source => _iconUrl(card.id, source),
          },
        },
    ],
    // Exactly what the TV arranges: cards placed nowhere are already in
    // their section, and cards that are gone are left out.
    'layout': config.layout
        .withCards(
          cards.map((card) => card.id),
          names: {for (final card in cards) card.id: card.sourceLabel},
        )
        .toJson(),
    // Pictures the user gave to cards that open a popup, by panel id.
    'panelIcons': {
      for (final panel in config.layout.panels)
        if (config.iconOverrides[PanelEntry.iconKey(panel.id)] case final path?)
          panel.id: _iconUrl(PanelEntry.iconKey(panel.id), path),
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
    'toasts': config.toasts.toJson(),
    // The values the user defined, and where the TV is said to be.
    'sources': [for (final source in config.sources) source.toJson()],
    'place': LauncherConfig.placeToJson(config.place),
    // Toasts and the now-playing widget stay empty without it.
    'notificationAccess': await ref.watch(notificationAccessProvider.future),
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
