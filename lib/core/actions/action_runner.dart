import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/actions/action_registry.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/entities.dart';

/// An act that cannot be run as written: it names no entity, an unknown one,
/// or one that does not present the action.
class ImproperAct extends FormatException {
  const ImproperAct(super.message);
}

/// Every action, once per name. All belong to some entity category.
List<ActionRegistry> get actionRegistries {
  final names = <String>{};
  return [
    for (final registry in entityRegistries)
      for (final action in registry.actions)
        if (names.add(action.name)) action,
  ];
}

ActionRegistry? actionRegistry(String name) =>
    actionRegistries.where((action) => action.name == name).firstOrNull;

/// [name] as [entity]'s category presents it.
ActionRegistry? actionFor(String name, Entity entity) =>
    entityRegistry(entity.category)?.actions
        .where((action) => action.name == name)
        .firstOrNull;

/// The entity [act] names among [entities], and the action as it presents it.
/// Throws [ImproperAct] if there is none.
({Entity entity, ActionRegistry action}) targetOf(
  Act act,
  Iterable<Entity> entities,
) {
  final id = act.arg(entityArg);
  if (id == null || id.isEmpty) {
    throw ImproperAct('"${act.name}" names no entity');
  }
  final entity = entities.byId(id);
  if (entity == null) throw ImproperAct('There is no entity "$id"');
  final action = actionFor(act.name, entity);
  if (action == null) {
    throw ImproperAct('${entity.label} has no "${act.name}"');
  }
  return (entity: entity, action: action);
}

/// Whether [act] can be run as written.
bool isProper(Act act, Iterable<Entity> entities) {
  try {
    targetOf(act, entities);
    return true;
  } on ImproperAct {
    return false;
  }
}

/// The entities that present [name], as editor choices. [sourceEntity] is
/// offered where more than one could do it.
Map<String, String> entitiesFor(String name, Iterable<Entity> entities) {
  final able = {
    for (final entity in entities)
      if (actionFor(name, entity) != null) entity.id: entity.label,
  };
  return {if (able.length != 1) sourceEntity: 'Its own source', ...able};
}

/// The editor's fields for one saved [act], given every entity.
List<ComponentOption> actOptions(
  Map<String, Object?> act, {
  Iterable<Entity> entities = const [],
}) {
  final action = actionRegistry('${act['do']}');
  return [
    ComponentOption(
      'do',
      'Does',
      OptionKind.choice,
      choices: {
        for (final action in actionRegistries) action.name: action.label,
      },
    ),
    ComponentOption(
      entityArg,
      'to',
      OptionKind.choice,
      choices: {
        // Keeps a saved target that is not among the choices.
        if (act[entityArg] case final String saved) saved: saved,
        ...entitiesFor('${act['do']}', entities),
      },
    ),
    for (final MapEntry(key: name, value: choices)
        in (action?.args ?? {}).entries)
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

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

class ActionRunner {
  ActionRunner(Ref ref) : _ref = ref;

  final Ref _ref;

  /// Runs [act] on the entity it names. Throws [ImproperAct] if it names
  /// none that can do it. Returns a message for the user, or null.
  Future<String?> run(
    Act act, {
    ActionScreen? screen,
    bool held = false,
    String? component,
  }) async {
    final (:entity, :action) = targetOf(
      act,
      await _ref.read(entitiesProvider.future),
    );
    return carryOut(
      action,
      ActionRun(_ref, act, entity, screen, held, component),
    );
  }

  /// Runs [action] locally. The web editor overrides this to forward device
  /// actions to the TV.
  @protected
  Future<String?> carryOut(ActionRegistry action, ActionRun run) =>
      action.run(run);
}
