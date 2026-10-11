import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// An act that cannot be run as written: it names no entity, an unknown one,
/// one without that action, or the action runs an operation there is none of.
class ImproperAct extends FormatException {
  const ImproperAct(super.message);
}

/// Every action name some entity in [entities] defines, with its label.
Map<String, String> actionLabels(Iterable<Entity> entities) => {
  for (final entity in entities)
    for (final MapEntry(key: name, value: action) in entity.actions.entries)
      name: action.label.isEmpty ? name : action.label,
};

/// The action called [name] as the first of [entities] that has one defines
/// it.
EntityAction? actionNamed(String name, Iterable<Entity> entities) {
  for (final entity in entities) {
    if (entity.actions[name] case final action?) return action;
  }
  return null;
}

/// The entity [act] names among [entities], and its action of that name.
/// Throws [ImproperAct] if there is none.
({Entity entity, EntityAction action}) targetOf(
  Act act,
  Iterable<Entity> entities,
) {
  final id = act.arg(entityArg);
  if (id == null || id.isEmpty) {
    throw ImproperAct('"${act.name}" names no entity');
  }
  final entity = entities.byId(id);
  if (entity == null) throw ImproperAct('There is no entity "$id"');
  final action = entity.actions[act.name];
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

/// The entities that define [name], as editor choices. [sourceEntity] is
/// offered where more than one could do it.
Map<String, String> entitiesFor(String name, Iterable<Entity> entities) {
  final able = {
    for (final entity in entities)
      if (entity.actions.containsKey(name)) entity.id: entity.label,
  };
  return {if (able.length != 1) sourceEntity: 'Its own source', ...able};
}

/// The editor's fields for one saved [act], given every entity. Its
/// arguments are those the entity it names lets an act add; for a target
/// only known when it runs, those of the first entity with that action.
List<ComponentOption> actOptions(
  Map<String, Object?> act, {
  Iterable<Entity> entities = const [],
}) {
  final name = '${act['do']}';
  final action =
      entities.byId(switch (act[entityArg]) {
        final String id => id,
        _ => null,
      })?.actions[name] ??
      actionNamed(name, entities);
  return [
    ComponentOption(
      'do',
      'Does',
      OptionKind.choice,
      choices: {
        // Keeps a saved action nothing defines now.
        if (act['do'] case final String saved) saved: saved,
        ...actionLabels(entities),
      },
    ),
    ComponentOption(
      entityArg,
      'to',
      OptionKind.choice,
      choices: {
        // Keeps a saved target that is not among the choices.
        if (act[entityArg] case final String saved) saved: saved,
        ...entitiesFor(name, entities),
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

  /// Has the entity [act] names do it: runs the operation its action names,
  /// with what the action binds and what the act adds. Throws [ImproperAct]
  /// if it cannot be done as written. Returns a message for the user, or
  /// null.
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
    final operation = _ref.read(operationsRegistryProvider)[action.run];
    if (operation == null) {
      throw ImproperAct(
        '"${act.name}" of ${entity.label} runs "${action.run}", '
        'which there is none of',
      );
    }
    final self = {'self': entity.self};
    return carryOut(
      operation,
      act,
      OperationRun(
        {
          for (final MapEntry(:key, :value) in action.bound.entries)
            key: value is String && value.contains('{{')
                ? readTemplate(_ref.read, value, self)
                : value,
          // Only what the action lets an act say.
          for (final name in action.args.keys)
            if (act.args.containsKey(name)) name: act.args[name],
        },
        screen: screen,
        held: held,
        component: component,
      ),
    );
  }

  /// Runs [operation] locally. The web editor overrides this to forward
  /// device operations to the TV, as the [act] that asked for them.
  @protected
  Future<String?> carryOut(Operation operation, Act act, OperationRun run) =>
      operation.run(run);
}
