import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// The argument that names the entity an action is done to, where that is
/// not the one it was set off from.
const entityArg = 'entity';

/// What can be done with any entity, whatever its kind, beside what its
/// kind presents.
final List<ActionKind> entityActions = [
  ActionKind(
    name: 'menu',
    label: 'Quick actions',
    icon: 'menu',
    run: (run) async {
      // The quick actions are a pane like any folder: told what they are
      // about, and opened, by its variables.
      run.ref.read(runtimeVarsProvider.notifier)
        ..set(Layout.menuId, LayoutItem.sourceVar, run.entity!.id)
        ..set(Layout.menuId, openVar, true);
      return null;
    },
  ),
  ActionKind(
    name: 'remove',
    label: 'Remove',
    icon: 'remove',
    run: (run) async {
      final entity = run.entity!;
      await run.ref.read(configProvider.notifier).removeEntity(entity.id);
      return '${entity.label} was removed. Add it again from the web page.';
    },
  ),
];

/// What the launcher does of itself, with no entity to do it to.
final List<ActionKind> launcherActions = [
  ActionKind(
    name: 'settings',
    label: 'Launcher settings',
    icon: 'settings',
    run: (run) async {
      await run.screen?.openSettings();
      return null;
    },
  ),
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
      run.ref.read(runtimeVarsProvider.notifier).set(component, name, value);
      return null;
    },
  ),
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
];

/// Every action there is, once each by name, for whatever offers them to
/// be chosen: those the kinds of entity present, those any entity has, and
/// the launcher's own. Read afresh, so a kind added later is among them.
List<ActionKind> get actionKinds {
  final names = <String>{};
  return [
    for (final action in [
      for (final kind in entityKinds) ...kind.actions,
      ...entityActions,
      ...launcherActions,
    ])
      if (names.add(action.name)) action,
  ];
}

/// The action called [name], as something to show; none for one made by a
/// newer launcher.
ActionKind? actionKind(String name) =>
    actionKinds.where((kind) => kind.name == name).firstOrNull;

/// Whether the action called [name] is done to an entity.
bool actionNeedsEntity(String name) =>
    !launcherActions.any((action) => action.name == name);

/// The action called [name] as [entity] presents it: its kind's, or one
/// any entity has; with no entity, or failing those, the launcher's own.
ActionKind? actionFor(String name, Entity? entity) {
  ActionKind? among(Iterable<ActionKind> actions) =>
      actions.where((action) => action.name == name).firstOrNull;
  return (entity == null
          ? null
          : among(entityKind(entity.kind)?.actions ?? const []) ??
                among(entityActions)) ??
      among(launcherActions);
}

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

/// Carries actions out, for the TV's screen and for anything else.
class ActionRunner {
  ActionRunner(this._ref);

  final Ref _ref;

  /// Whether [act] can be done with [subject] as the entity it was set off
  /// from. One that names its own entity is taken at its word.
  bool applies(Act act, Entity? subject) =>
      act.arg(entityArg) != null || actionFor(act.name, subject) != null;

  /// Does [act] to the entity it names, or failing that to [subject]. What
  /// cannot be done, for want of an entity that presents it or of a
  /// [screen], is left undone. Returns something to tell the user, if
  /// there is anything.
  Future<String?> run(
    Act act, {
    Entity? subject,
    ActionScreen? screen,
    bool held = false,
    String? component,
  }) async {
    var entity = subject;
    if (act.arg(entityArg) case final id?) {
      final entities = await _ref.read(entitiesProvider.future);
      entity = entities.where((entity) => entity.id == id).firstOrNull;
      // Named, and not there: nothing to do it to.
      if (entity == null) return null;
    }
    final kind = actionFor(act.name, entity);
    if (kind == null) return null;
    return kind.run(ActionRun(_ref, act, entity, screen, held, component));
  }
}
