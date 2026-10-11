import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';

/// The launcher's own settings, placed like an app.
const settingsEntity = Entity(
  id: 'launcher:settings',
  category: launcherCategory,
  label: 'Settings',
  prefab: cardPrefabId,
  placed: true,
  data: {
    Entity.icon:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
        'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
        'stroke-linejoin="round"><circle cx="80" cy="45" r="7"/>'
        '<circle cx="80" cy="45" r="17"/><path d="M80 20v8m0 34v8M55 45h8'
        'm34 0h8M62.3 27.3l5.7 5.7m24 24 5.7 5.7m0-35.4L92 33M68 57l-5.7 '
        '5.7"/></svg>',
    Entity.shape: Entity.lineArt,
  },
  actions: {
    'open': EntityAction(run: 'openSettings', label: 'Open', icon: 'play'),
  },
);

// `of` is a component id; empty for the one the act fired from.
const _of = {'of': <String>[]};

/// The entities there are on every TV, as data. None is saved.
const builtInEntities = [
  settingsEntity,
  Entity(
    id: 'clock',
    category: 'clock',
    label: 'Clock',
    prefab: 'clock',
    feed: Feed('clock'),
  ),
  Entity(
    id: 'weather',
    category: 'weather',
    label: 'Weather',
    prefab: 'weather',
    feed: Feed('weather'),
  ),
  Entity(
    id: 'location',
    category: 'location',
    label: 'Location',
    feed: Feed('location'),
  ),
  Entity(
    id: 'media',
    category: 'media',
    label: 'Media Player',
    prefab: 'now-playing',
    feed: Feed('media'),
    actions: {
      'playPause': EntityAction(
        run: 'mediaCommand',
        bound: {'command': 'playPause'},
        label: 'Play or pause',
        icon: 'pause',
      ),
      'next': EntityAction(
        run: 'mediaCommand',
        bound: {'command': 'next'},
        label: 'Next',
        icon: 'next',
      ),
      'previous': EntityAction(
        run: 'mediaCommand',
        bound: {'command': 'previous'},
        label: 'Previous',
        icon: 'previous',
      ),
    },
  ),
  Entity(
    id: 'system',
    category: 'system',
    label: 'System',
    actions: {
      'setup': EntityAction(
        run: 'runSetup',
        label: 'Set up automatically',
        icon: 'settings',
      ),
      'homeButton': EntityAction(
        run: 'setHomeButton',
        args: {
          'enabled': ['true', 'false'],
        },
        label: 'Switch the Home button',
        icon: 'home',
      ),
      'tvSettings': EntityAction(
        run: 'openTvSettings',
        label: 'TV settings',
        icon: 'tv',
      ),
    },
  ),
  Entity(
    id: 'layers',
    category: 'layers',
    label: 'Layers',
    feed: Feed('layers'),
    actions: {
      'newLayer': EntityAction(
        run: 'newLayer',
        args: {
          'blur': [],
          'dim': [],
          'modal': ['true', 'false'],
        },
        label: 'Create a new layer',
        icon: 'apps',
      ),
      'toLayer': EntityAction(
        run: 'toLayer',
        args: _of,
        label: 'Move to the top layer',
        icon: 'apps',
      ),
      'closeLayer': EntityAction(
        run: 'closeLayer',
        args: _of,
        label: 'Remove its layer',
        icon: 'close',
      ),
      'close': EntityAction(
        run: 'closePopup',
        label: 'Close the popup',
        icon: 'close',
      ),
    },
  ),
  Entity(
    id: 'variables',
    category: 'variables',
    label: 'Variables',
    actions: {
      'set': EntityAction(
        run: 'setVariable',
        args: {'var': [], 'value': [], ..._of},
        label: 'Set a variable',
        icon: 'star',
      ),
    },
  ),
];

/// Ids an entity the user makes may not take: the built-in ones, and names
/// templates read.
final reservedIds = {
  for (final entity in builtInEntities) entity.id,
  'source',
  'self',
};
