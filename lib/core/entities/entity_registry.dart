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

/// One category of entity: how its entities are listed, their actions and
/// their live data. A new category is one entry in [entityRegistries].
class EntityRegistry {
  const EntityRegistry({
    required this.name,
    required this.label,
    required this.list,
    this.actions = const [],
    this.data,
    this.prefab,
    this.placed = false,
  }) : one = null;

  /// A category with exactly one entity, whose id is the category name.
  EntityRegistry.single({
    required this.name,
    required this.label,
    this.actions = const [],
    this.data,
    this.prefab,
  }) : placed = false,
       one = Entity(id: name, category: name, label: label),
       list = ((ref) async => [Entity(id: name, category: name, label: label)]);

  /// The single entity, for a [EntityRegistry.single] category.
  final Entity? one;

  /// The category name, as [Entity.category] has it.
  final String name;

  /// Plural display name, e.g. "Apps".
  final String label;

  /// Lists the current entities; re-run when what it watches changes.
  final Future<List<Entity>> Function(Ref ref) list;

  final List<ActionKind> actions;

  /// Live data merged over [Entity.data]; `text` is the whole-value form.
  final Object? Function(Ref ref, Entity entity)? data;

  /// The prefab the editor offers this category as, if any.
  final String? prefab;

  /// Whether unplaced entities are added to the inbox (apps, inputs).
  final bool placed;
}

final List<EntityRegistry> entityRegistries = [
  EntityRegistry(
    name: inputCategory,
    label: 'Inputs',
    prefab: cardPrefabId,
    placed: true,
    list: (ref) async => [
      for (final input in await ref.watch(tvInputsProvider.future))
        Entity(
          id: Entity.inputId(input.id),
          category: inputCategory,
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
  EntityRegistry(
    name: appCategory,
    label: 'Apps',
    prefab: cardPrefabId,
    placed: true,
    list: (ref) async => [
      for (final app in await ref.watch(installedAppsProvider.future))
        Entity(
          id: Entity.appId(app.packageName),
          category: appCategory,
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
          // Fall back to the TV's app info screen.
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
  EntityRegistry(
    name: launcherCategory,
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
  EntityRegistry.single(
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
  EntityRegistry.single(
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
      if (weather == null) return const {'text': null};
      return {
        'text': '${weather.temperature.round()}°',
        'temperature': weather.temperature,
        'high': weather.high,
        'low': weather.low,
        'description': weather.description,
        'sky': weather.sky.name,
        'place': place!.name,
      };
    },
  ),
  EntityRegistry.single(
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
  EntityRegistry.single(
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
  EntityRegistry.single(
    name: 'system',
    label: 'System',
    actions: [
      // The message's first line is its heading.
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
          // Setup changes what the launcher can see.
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
  EntityRegistry.single(
    name: 'layers',
    label: 'Layers',
    data: (ref, entity) => {'count': ref.watch(layersProvider).length},
    actions: [
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
  EntityRegistry.single(
    name: 'variables',
    label: 'Variables',
    actions: [
      // Runtime only; not saved.
      ActionKind(
        name: 'set',
        label: 'Set a variable',
        icon: 'star',
        args: const {'var': [], 'value': [], 'of': []},
        run: (run) async {
          // Defaults to the component that fired it.
          final component = run.act.arg('of') ?? run.component;
          final name = run.act.arg('var');
          if (component == null || name == null) return null;
          final value = switch (run.act.args['value']) {
            // Evaluated now, so a toggle can read its own value.
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
  EntityRegistry.single(
    name: 'layout',
    label: 'Layout',
    actions: [
      ActionKind(
        name: 'remove',
        label: 'Remove',
        icon: 'remove',
        args: const {'what': []},
        run: (run) async {
          // `what` is an entity id; every instance handed it is removed.
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
  // User-defined values: a web address or fixed text.
  EntityRegistry(
    name: 'value',
    label: 'Values',
    list: (ref) async => [
      for (final source in await ref.watch(
        configProvider.selectAsync((config) => config.sources),
      ))
        Entity(
          id: source.id,
          category: 'value',
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

String _package(ActionRun run) => run.entity!.data['package']! as String;

Place? _place(Ref ref) =>
    ref.watch(configProvider.select((config) => config.value?.place));

EntityRegistry? entityRegistry(String name) =>
    entityRegistries.where((kind) => kind.name == name).firstOrNull;

/// Sort position of [name]; unknown categories go last.
int entityRegistryIndex(String name) =>
    switch (entityRegistries.indexWhere((kind) => kind.name == name)) {
      -1 => entityRegistries.length,
      final index => index,
    };
