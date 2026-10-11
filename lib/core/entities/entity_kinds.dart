import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/input_artwork.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/values/data_source.dart';
import 'package:openlauncher/core/values/date_format.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// A kind of entity: where the entities of that kind come from, and the
/// actions each of them presents, which are what a trigger of anything
/// drawn from one can set off.
///
/// **This list is the one place a kind of entity is defined.** Apps are one
/// kind among however many: a new kind (a device in the house, a contact,
/// a channel) is a new entry here, saying how its entities are listed and
/// what can be done with one. Nothing else needs to know of it: the layout
/// holds entities by id, prefabs read them through `{{source...}}`, and
/// the editor lists and offers whatever is here.
class EntityKind {
  const EntityKind({
    required this.name,
    required this.label,
    required this.list,
    this.actions = const [],
    this.data,
    this.prefab,
  });

  /// How an [Entity] names it.
  final String name;

  /// What entities of this kind are called, together: "Apps".
  final String label;

  /// The entities of this kind there are now. Watches whatever it reads,
  /// so that it is asked again when that changes.
  final Future<List<Entity>> Function(Ref ref) list;

  /// What can be done with an entity of this kind, in the order offered.
  final List<ActionKind> actions;

  /// What an entity of this kind provides beside its name, for whatever
  /// shows it: a map of its parts, in which `text` is how it reads whole.
  /// Watches whatever it is made from, so that what shows it is told when
  /// it changes. None for a kind that provides nothing more.
  final Object? Function(Ref ref, Entity entity)? data;

  /// The id of the prefab an entity of this kind is put on the screen as
  /// when it turns up placed nowhere, as a newly installed app does. None
  /// for a kind whose entities are only read and acted on, not placed of
  /// themselves: the clock, the media player.
  final String? prefab;
}

final List<EntityKind> entityKinds = [
  EntityKind(
    name: inputKind,
    label: 'Inputs',
    prefab: cardPrefabId,
    data: _pictured,
    list: (ref) async => [
      for (final input in await ref.watch(tvInputsProvider.future))
        Entity(
          id: Entity.inputId(input.id),
          kind: inputKind,
          target: input.id,
          label: input.label,
          svg: inputArtworkSvg(input.kind, input.label),
        ),
    ],
    actions: [
      ActionKind(
        name: 'open',
        label: 'Open',
        icon: 'play',
        run: (run) async {
          await run.platform.switchToInput(run.entity!.target);
          return null;
        },
      ),
    ],
  ),
  EntityKind(
    name: appKind,
    label: 'Apps',
    prefab: cardPrefabId,
    data: _pictured,
    list: (ref) async => [
      for (final app in await ref.watch(installedAppsProvider.future))
        Entity(
          id: Entity.appId(app.packageName),
          kind: appKind,
          target: app.packageName,
          label: app.label,
          iconPath: app.iconPath,
          wideIcon: app.isBanner,
        ),
    ],
    actions: [
      ActionKind(
        name: 'open',
        label: 'Open',
        icon: 'play',
        run: (run) async {
          await run.platform.launchApp(run.entity!.target);
          return null;
        },
      ),
      ActionKind(
        name: 'info',
        label: 'App info',
        icon: 'info',
        run: (run) async {
          await run.platform.openAppInfo(run.entity!.target);
          return null;
        },
      ),
      ActionKind(
        name: 'forceStop',
        label: 'Force stop',
        icon: 'stop',
        run: (run) async {
          final app = run.entity!;
          if (await run.platform.forceStopApp(app.target)) {
            return '${app.label} was stopped.';
          }
          // The launcher could not do it; the TV's own screen can.
          await run.platform.openAppInfo(app.target);
          return 'Choose "Force stop" here. Run automatic setup in Settings '
              'to stop apps straight from the menu.';
        },
      ),
      ActionKind(
        name: 'uninstall',
        label: 'Uninstall',
        icon: 'delete',
        run: (run) async {
          await run.platform.uninstallApp(run.entity!.target);
          return null;
        },
      ),
    ],
  ),
  // The launcher's own screens; there is only the one so far.
  EntityKind(
    name: launcherKind,
    label: 'Launcher',
    prefab: cardPrefabId,
    data: _pictured,
    list: (ref) async => const [Entity.settings],
    actions: [
      ActionKind(
        name: 'open',
        label: 'Open',
        icon: 'play',
        run: (run) async {
          await run.screen?.openSettings();
          return null;
        },
      ),
    ],
  ),
  // What the launcher knows of the time, the place and what plays: there
  // to be read, and in the media player's case told what to do.
  EntityKind(
    name: 'clock',
    label: 'Clock',
    list: (ref) async => const [
      Entity(id: 'clock', kind: 'clock', target: '', label: 'Clock'),
    ],
    data: (ref, entity) {
      final now = ref.watch(tickProvider(true));
      final time = formatDateTime(now, 'HH:mm');
      return {
        'text': time,
        'time': time,
        'date': formatDateTime(now, 'EEEE d MMMM'),
        'hour': now.hour,
        'minute': now.minute,
        'second': now.second,
        'hour12': now.hour % 12 == 0 ? 12 : now.hour % 12,
        'ampm': now.hour < 12 ? 'am' : 'pm',
        'weekday': dayNames[now.weekday - 1],
        'day': now.day,
        'month': now.month,
        'monthName': monthNames[now.month - 1],
        'year': now.year,
        'epoch': now.millisecondsSinceEpoch,
      };
    },
  ),
  EntityKind(
    name: 'weather',
    label: 'Weather',
    list: (ref) async => const [
      Entity(id: 'weather', kind: 'weather', target: '', label: 'Weather'),
    ],
    data: (ref, entity) {
      final place = _place(ref);
      final weather = place == null
          ? null
          : ref
                .watch(
                  weatherProvider((
                    latitude: place.latitude,
                    longitude: place.longitude,
                    fahrenheit: false,
                  )),
                )
                .value;
      // Nothing to say until there is a place and its weather has come.
      if (weather == null) return const {'text': null};
      return {
        'text': '${weather.temperature.round()}°',
        'temperature': weather.temperature,
        'high': weather.high,
        'low': weather.low,
        'description': weather.description,
      };
    },
  ),
  EntityKind(
    name: 'location',
    label: 'Location',
    list: (ref) async => const [
      Entity(id: 'location', kind: 'location', target: '', label: 'Location'),
    ],
    data: (ref, entity) {
      final place = _place(ref);
      if (place == null) return const {'text': null};
      return {
        'text': place.name,
        'name': place.name,
        'latitude': place.latitude,
        'longitude': place.longitude,
      };
    },
  ),
  EntityKind(
    name: 'media',
    label: 'Media Player',
    list: (ref) async => const [
      Entity(id: 'media', kind: 'media', target: '', label: 'Media Player'),
    ],
    data: (ref, entity) {
      final playing = ref.watch(nowPlayingProvider).value;
      if (playing == null) return const {'text': null, 'playing': false};
      return {
        'text': playing.title ?? playing.appLabel,
        'title': playing.title,
        'artist': playing.artist,
        'app': playing.appLabel,
        'playing': playing.playing,
        'art': playing.artPath,
      };
    },
    actions: [
      for (final (command, label, icon) in const [
        (MediaCommand.playPause, 'Play or pause', 'pause'),
        (MediaCommand.next, 'Next', 'next'),
        (MediaCommand.previous, 'Previous', 'previous'),
      ])
        ActionKind(
          name: command.name,
          label: label,
          icon: icon,
          run: (run) async {
            await run.platform.sendMediaCommand(command);
            return null;
          },
        ),
    ],
  ),
  // A value the user defined: what a web address answers, or fixed text.
  EntityKind(
    name: 'value',
    label: 'Values',
    list: (ref) async => [
      for (final source in await ref.watch(
        configProvider.selectAsync((config) => config.sources),
      ))
        Entity(
          id: source.id,
          kind: 'value',
          target: source.id,
          label: source.name.isEmpty ? source.id : source.name,
        ),
    ],
    data: (ref, entity) {
      final source = ref.watch(
        configProvider.select(
          (config) => config.value?.sources
              .where((source) => source.id == entity.id)
              .firstOrNull,
        ),
      );
      return switch (source) {
        null => null,
        DataSource(kind: SourceKind.text, :final text) => text,
        _ => ref.watch(sourceValueProvider(source)).value,
      };
    },
  ),
];

/// What an entity that is put on the screen as a picture and a name
/// provides: the picture, and how it is to sit in its frame.
Map<String, Object?> _pictured(Ref ref, Entity entity) {
  // Artwork drawn for the whole frame fills it; an icon sits in it.
  final fills = entity.wideIcon || entity.iconPath == null;
  return {
    'icon': entity.iconPath ?? entity.svg,
    'fit': entity.wideIcon ? 'cover' : 'contain',
    'pad': fills ? 0 : 14,
    'padSmall': fills ? 0 : 4,
  };
}

/// Where the user said the TV is.
Place? _place(Ref ref) =>
    ref.watch(configProvider.select((config) => config.value?.place));

/// The kind called [name]; none for one a newer launcher knows.
EntityKind? entityKind(String name) =>
    entityKinds.where((kind) => kind.name == name).firstOrNull;

/// Where the kind called [name] comes among the kinds; after them all for
/// one that is not known.
int entityKindIndex(String name) =>
    switch (entityKinds.indexWhere((kind) => kind.name == name)) {
      -1 => entityKinds.length,
      final index => index,
    };
