import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_kind.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/entities.dart';

/// The argument naming the entity that does an action.
const entityArg = 'entity';

/// Every action, once per name. All belong to some entity category.
List<ActionKind> get actionKinds {
  final names = <String>{};
  return [
    for (final kind in entityRegistries)
      for (final action in kind.actions)
        if (names.add(action.name)) action,
  ];
}

/// The editor's fields for one saved [act]. [entities] are the ids it could
/// target, with their labels.
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

/// The single-entity category that presents [name], so the action needs no
/// entity named. Null if only multi-entity categories have it.
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

/// Whether [name] must be given an entity.
bool actionNeedsEntity(String name) => ownerOf(name) == null;

/// [name] as [entity]'s category presents it, else as its single owner does.
ActionKind? actionFor(String name, Entity? entity) =>
    _among(entityRegistry(entity?.category ?? '')?.actions, name) ??
    ownerOf(name)?.action;

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

class ActionRunner {
  ActionRunner(Ref ref) : _ref = ref;

  final Ref _ref;

  /// Whether [act] can run with [subject] as its default entity.
  bool applies(Act act, Entity? subject) =>
      act.arg(entityArg) != null || actionFor(act.name, subject) != null;

  /// Runs [act] on the entity it names, else [subject], else the action's
  /// single owner. Does nothing if none presents it. Returns a message for
  /// the user, or null.
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
      if (entity == null) return null;
    }
    var kind = _among(
      entityRegistry(entity?.category ?? '')?.actions,
      act.name,
    );
    if (kind == null) {
      // Fall back to the single owner.
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

  /// Runs [kind] locally. The web editor overrides this to forward device
  /// actions to the TV.
  @protected
  Future<String?> carryOut(ActionKind kind, ActionRun run) => kind.run(run);
}
