import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/entities.dart';

/// The argument that names the entity an action is done to, where that is
/// not the one it was set off from.
const entityArg = 'entity';

/// Every action there is, once each by name, for whatever offers them to
/// be chosen. Each is some kind of entity's: there is none that belongs to
/// nothing. Read afresh, so a kind added later is among them.
List<ActionKind> get actionKinds {
  final names = <String>{};
  return [
    for (final kind in entityRegistries)
      for (final action in kind.actions)
        if (names.add(action.name)) action,
  ];
}

/// The action called [name], as something to show; none for one made by a
/// newer launcher.
/// What there is to set about one action of a chain, [act] as it is
/// saved: which it is, and whatever one of that kind is told. [entities]
/// are those it could be done to, by id, with what each is called. The
/// editor's form for a chain is made from this.
List<ComponentOption> actOptions(
  Map<String, Object?> act, {
  Map<String, String> entities = const {},
}) {
  final kind = actionKind('${act['do']}');
  return [
    ComponentOption(
      'do',
      'Does',
      OptionKind.choice,
      choices: {for (final kind in actionKinds) kind.name: kind.label},
    ),
    if (kind != null && actionNeedsEntity(kind.name) && entities.isNotEmpty)
      ComponentOption(
        entityArg,
        'to',
        OptionKind.choice,
        unset: 'Its own source',
        choices: entities,
      ),
    for (final MapEntry(key: name, value: choices)
        in (kind?.args ?? {}).entries)
      choices.isEmpty
          ? ComponentOption(
              name,
              name == 'of' ? 'of (an id; empty for itself)' : name,
              OptionKind.value,
            )
          : ComponentOption(
              name,
              name,
              OptionKind.choice,
              choices: {for (final choice in choices) choice: choice},
            ),
  ];
}

ActionKind? actionKind(String name) =>
    actionKinds.where((kind) => kind.name == name).firstOrNull;

ActionKind? _among(Iterable<ActionKind>? actions, String name) =>
    actions?.where((action) => action.name == name).firstOrNull;

/// The entity that presents the action called [name] with no need to be
/// told which entity is meant, there being only the one of its kind: the
/// layers, the system. None for an action of a kind there are many of, as
/// opening is of apps.
({Entity entity, ActionKind action})? ownerOf(String name) {
  for (final kind in entityRegistries) {
    if ((kind.one, _among(kind.actions, name)) case (
      final entity?,
      final action?,
    )) {
      return (entity: entity, action: action);
    }
  }
  return null;
}

/// Whether the action called [name] has to be told which entity it is
/// done to, or has one to set it off from.
bool actionNeedsEntity(String name) => ownerOf(name) == null;

/// The action called [name] as [entity] presents it, which is its kind's;
/// failing that, as the one entity presents it that needs no naming.
ActionKind? actionFor(String name, Entity? entity) =>
    _among(entityRegistry(entity?.category ?? '')?.actions, name) ??
    ownerOf(name)?.action;

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

/// Carries actions out, for the TV's screen and for anything else.
class ActionRunner {
  ActionRunner(Ref ref) : _ref = ref;

  final Ref _ref;

  /// Whether [act] can be done with [subject] as the entity it was set off
  /// from. One that names its own entity is taken at its word.
  bool applies(Act act, Entity? subject) =>
      act.arg(entityArg) != null || actionFor(act.name, subject) != null;

  /// Has the entity [act] names do it, or failing that [subject], or
  /// failing that the one entity that presents such an action without
  /// being named. What cannot be done, for want of an entity that
  /// presents it or of a [screen], is left undone. Returns something to tell the user, if
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
      entity = entities.byId(id);
      // Named, and not there: nothing to do it to.
      if (entity == null) return null;
    }
    var kind = _among(
      entityRegistry(entity?.category ?? '')?.actions,
      act.name,
    );
    if (kind == null) {
      // Not that entity's: then the one's that needs no naming.
      final owner = ownerOf(act.name);
      if (owner == null) return null;
      kind = owner.action;
      entity = owner.entity;
    }
    return carryOut(
      kind,
      ActionRun(_ref, act, entity, screen, held, component),
    );
  }

  /// Does [kind] as [run] has it: here. A runner that is not on the TV has
  /// the TV do what only it can.
  @protected
  Future<String?> carryOut(ActionKind kind, ActionRun run) => kind.run(run);
}
