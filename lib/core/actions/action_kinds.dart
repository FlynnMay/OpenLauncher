import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';

/// The argument whose value is the id of a popup.
const panelArg = 'panel';

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
      await run.screen?.openPanel(Layout.menuId, subject: run.entity);
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
    name: 'panel',
    label: 'Open a folder',
    icon: 'folder',
    args: const {panelArg: []},
    run: (run) async {
      if (run.act.arg(panelArg) case final id?) {
        await run.screen?.openPanel(id);
      }
      return null;
    },
  ),
  ActionKind(
    name: 'settings',
    label: 'Launcher settings',
    icon: 'settings',
    run: (run) async {
      await run.screen?.openSettings();
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
    return kind.run(ActionRun(_ref, act, entity, screen, held));
  }
}
