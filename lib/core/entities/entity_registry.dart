import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/input_artwork.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/values/data_source.dart';
import 'package:openlauncher/core/values/date_format.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher/core/variables/scope.dart';
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
    this.placed = false,
  }) : one = null;

  /// A kind there is only the one entity of, which goes by the kind's own
  /// name: the clock, the system. Its actions need not be told which
  /// entity is meant.
  EntityKind.single({
    required this.name,
    required this.label,
    this.actions = const [],
    this.data,
    this.prefab,
  }) : placed = false,
       one = Entity(id: name, kind: name, label: label),
       list = ((ref) async => [Entity(id: name, kind: name, label: label)]);

  /// The one entity there is of this kind, for a kind there is one of.
  final Entity? one;

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

  /// The id of the prefab an entity of this kind is put on the screen as,
  /// when it is: what the editor offers it as. None for a kind there is no
  /// ready way of showing.
  final String? prefab;

  /// True for a kind whose entities go on the screen of themselves when
  /// they turn up placed nowhere, as a newly installed app does. The rest,
  /// such as the clock, are there only where the user puts them.
  final bool placed;
}

final List<EntityKind> entityKinds = [
  EntityKind(
    name: inputKind,
    label: 'Inputs',
    prefab: cardPrefabId,
    placed: true,
    list: (ref) async => [
      for (final input in await ref.watch(tvInputsProvider.future))
        Entity(
          id: Entity.inputId(input.id),
          kind: inputKind,
          label: input.label,
          data: {
            'input': input.id,
            Entity.icon: inputArtworkSvg(input.kind, input.label),
            Entity.shape: Entity.lineArt,
          },
        ),
    ],
    actions: [
      ActionKind(
        name: 'open',
        label: 'Open',
        icon: 'play',
        onDevice: true,
        run: (run) async {
          await run.platform.switchToInput(
            run.entity!.data['input']! as String,
          );
          return null;
        },
      ),
    ],
  ),
  EntityKind(
    name: appKind,
    label: 'Apps',
    prefab: cardPrefabId,
    placed: true,
    list: (ref) async => [
      for (final app in await ref.watch(installedAppsProvider.future))
        Entity(
          id: Entity.appId(app.packageName),
          kind: appKind,
          label: app.label,
          data: {
            'package': app.packageName,
            Entity.icon: ?app.iconPath,
            if (app.iconPath != null)
              Entity.shape: app.isBanner ? Entity.banner : 'icon',
          },
        ),
    ],
    actions: [
      ActionKind(
        name: 'open',
        label: 'Open',
        icon: 'play',
        onDevice: true,
        run: (run) async {
          await run.platform.launchApp(_package(run));
          return null;
        },
      ),
      ActionKind(
        name: 'info',
        onDevice: true,
        label: 'App info',
        icon: 'info',
        run: (run) async {
          await run.platform.openAppInfo(_package(run));
          return null;
        },
      ),
      ActionKind(
        name: 'forceStop',
        onDevice: true,
        label: 'Force stop',
        icon: 'stop',
        run: (run) async {
          final app = run.entity!;
          if (await run.platform.forceStopApp(_package(run))) {
            return '${app.label} was stopped.';
          }
          // The launcher could not do it; the TV's own screen can.
          await run.platform.openAppInfo(_package(run));
          return 'Choose "Force stop" here. Run automatic setup in Settings '
              'to stop apps straight from the menu.';
        },
      ),
      ActionKind(
        name: 'uninstall',
        onDevice: true,
        label: 'Uninstall',
        icon: 'delete',
        run: (run) async {
          await run.platform.uninstallApp(_package(run));
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
    placed: true,
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
  EntityKind.single(
    name: 'clock',
    label: 'Clock',
    prefab: 'clock',
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
  EntityKind.single(
    name: 'weather',
    label: 'Weather',
    prefab: 'weather',
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
        // The sky, in a word; what to draw for it is the prefab's to say.
        'sky': weather.sky.name,
        'place': place!.name,
      };
    },
  ),
  EntityKind.single(
    name: 'location',
    label: 'Location',
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
  EntityKind.single(
    name: 'media',
    label: 'Media Player',
    prefab: 'now-playing',
    data: (ref, entity) {
      final playing = ref.watch(nowPlayingProvider).value;
      if (playing == null) {
        return const {'text': null, 'playing': false};
      }
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
          onDevice: true,
          run: (run) async {
            await run.platform.sendMediaCommand(command);
            return null;
          },
        ),
    ],
  ),
  // The launcher and the TV it is on: there is the one, which needs no
  // naming.
  EntityKind.single(
    name: 'system',
    label: 'System',
    actions: [
      // What the launcher needs of the TV to do all it can. What it says of
      // how that went has its heading on a line of its own.
      ActionKind(
        name: 'setup',
        label: 'Set up automatically',
        icon: 'settings',
        onDevice: true,
        run: (run) async {
          SetupResult result;
          try {
            result = await run.platform.runAutomaticSetup();
          } on Object catch (error) {
            result = SetupResult(
              outcome: SetupOutcome.failed,
              detail: '$error',
            );
          }
          // Setup also lets the launcher see notifications and what is playing.
          run.ref
            ..invalidate(homeButtonEnabledProvider)
            ..invalidate(canManageHomeButtonProvider)
            ..invalidate(notificationAccessProvider)
            ..invalidate(nowPlayingProvider);
          return switch (result.outcome) {
            SetupOutcome.done =>
              'All set\n'
                  'The Home button on your remote now opens OpenLauncher.',
            SetupOutcome.adbUnavailable =>
              'USB debugging is off\n'
                  'OpenLauncher sets itself up through the TV\'s debugging '
                  'service.\n\n'
                  'In TV settings, go to System → About and press OK on the '
                  'build number seven times. Then turn on USB debugging in '
                  'System → Developer options, and try again.',
            SetupOutcome.notAuthorised =>
              'The TV did not allow it\n'
                  'Try again, and when the TV asks whether to allow USB '
                  'debugging, tick "Always allow" and choose Allow.',
            SetupOutcome.failed =>
              'Setup did not finish\n'
                  '${result.detail ?? 'Something went wrong. Try again.'}',
          };
        },
      ),
      ActionKind(
        name: 'homeButton',
        label: 'Switch the Home button',
        icon: 'home',
        args: const {
          'enabled': ['true', 'false'],
        },
        onDevice: true,
        run: (run) async {
          await run.platform.setHomeButtonEnabled(
            switch (run.act.args['enabled']) {
              false || 'false' => false,
              _ => true,
            },
          );
          run.ref.invalidate(homeButtonEnabledProvider);
          return null;
        },
      ),
      ActionKind(
        name: 'tvSettings',
        label: 'TV settings',
        icon: 'tv',
        onDevice: true,
        run: (run) async {
          await run.platform.openHomeButtonSettings();
          return null;
        },
      ),
    ],
  ),
  // What is drawn over the home screen, and over what.
  EntityKind.single(
    name: 'layers',
    label: 'Layers',
    data: (ref, entity) => {'count': ref.watch(layersProvider).length},
    actions: [
      // Layers: what is moved to one is drawn over all below it, which the
      // layer may blur or darken.
      ActionKind(
        name: 'newLayer',
        label: 'Create a new layer',
        icon: 'apps',
        args: const {
          'blur': [],
          'dim': [],
          'modal': ['true', 'false'],
        },
        run: (run) async {
          double number(String key) => switch (run.act.args[key]) {
            final num number => number.toDouble(),
            final String text => double.tryParse(text) ?? 0,
            _ => 0,
          };
          run.ref
              .read(layersProvider.notifier)
              .create(
                blur: number('blur'),
                dim: number('dim'),
                modal: switch (run.act.args['modal']) {
                  true || 'true' => true,
                  _ => false,
                },
              );
          return null;
        },
      ),
      ActionKind(
        name: 'toLayer',
        label: 'Move to the top layer',
        icon: 'apps',
        args: const {'of': []},
        run: (run) async {
          if (run.act.arg('of') ?? run.component case final component?) {
            run.ref.read(layersProvider.notifier).moveToTop(component);
          }
          return null;
        },
      ),
      ActionKind(
        name: 'closeLayer',
        label: 'Take its layer away',
        icon: 'close',
        args: const {'of': []},
        run: (run) async {
          run.ref
              .read(layersProvider.notifier)
              .close(run.act.arg('of') ?? run.component);
          return null;
        },
      ),
      ActionKind(
        name: 'close',
        label: 'Close the popup',
        icon: 'close',
        run: (run) async {
          run.screen?.close();
          return null;
        },
      ),
    ],
  ),
  // The variables components have, as they stand while the launcher runs.
  EntityKind.single(
    name: 'variables',
    label: 'Variables',
    actions: [
      // Sets a variable while the launcher runs; whatever reads it follows.
      ActionKind(
        name: 'set',
        label: 'Set a variable',
        icon: 'star',
        args: const {'var': [], 'value': [], 'of': []},
        run: (run) async {
          // On the component named, or the one this was set off from.
          final component = run.act.arg('of') ?? run.component;
          final name = run.act.arg('var');
          if (component == null || name == null) return null;
          final value = switch (run.act.args['value']) {
            // What it comes to now, so one press can undo the last:
            // `{{menu.open == true ? false : true}}`.
            final String text when text.contains('{{') => readTemplate(
              run.ref.read,
              text,
              const {},
            ),
            final value => value,
          };
          run.ref
              .read(runtimeVarsProvider.notifier)
              .set(component, name, value);
          return null;
        },
      ),
    ],
  ),
  // What is on the screen and where.
  EntityKind.single(
    name: 'layout',
    label: 'Layout',
    actions: [
      ActionKind(
        name: 'remove',
        label: 'Remove',
        icon: 'remove',
        args: const {'what': []},
        run: (run) async {
          // What is taken off is an entity, by its id: everything on the
          // screen that was handed it goes, and it is not put back.
          final id = run.act.arg('what');
          if (id == null) return null;
          final entities = await run.ref.read(entitiesProvider.future);
          await run.ref.read(configProvider.notifier).removeEntity(id);
          final label = entities.byId(id)?.label ?? id;
          return '$label was removed. Add it again from the web page.';
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

/// The package of the app [run] is about.
String _package(ActionRun run) => run.entity!.data['package']! as String;

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
