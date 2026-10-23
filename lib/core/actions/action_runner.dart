import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// An act that cannot be run as written: it names no entity, an unknown one,
/// one without that action, or an address there is no operation at.
class ImproperAct extends FormatException {
  const ImproperAct(super.message);
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

/// Whether [act] can be run as written. An address is checked as it runs.
bool isProper(Act act, Iterable<Entity> entities) {
  if (act.isAddress) return true;
  try {
    targetOf(act, entities);
    return true;
  } on ImproperAct {
    return false;
  }
}

/// The actions an act aimed at [target] can name: that entity's, or the
/// first of each name among every entity's when the target is only known as
/// it runs.
Map<String, EntityAction> actionsOf(String? target, Iterable<Entity> entities) {
  if (entities.byId(target) case final entity?) return entity.actions;
  final everyAction = entities.expand((entity) => entity.actions.entries);
  final firstOfEach = <String, EntityAction>{};
  for (final MapEntry(key: name, value: action) in everyAction) {
    firstOfEach.putIfAbsent(name, () => action);
  }
  return firstOfEach;
}

/// [act] aimed at [target] doing [name]: keeps the arguments that action
/// lets an act add.
Act retargeted(Act act, String target, String name, EntityAction? action) =>
    Act(name, {
      entityArg: target,
      for (final MapEntry(:key, :value) in act.args.entries)
        if (action?.args.containsKey(key) ?? false) key: value,
    });

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

class ActionRunner {
  ActionRunner(Ref ref) : _ref = ref;

  final Ref _ref;

  /// Runs [act]'s operation: the address's, or the one its entity's action
  /// names. Returns a message for the user, or null; throws [ImproperAct] if
  /// it cannot be done as written.
  Future<String?> run(
    Act act, {
    ActionScreen? screen,
    bool held = false,
    String? component,
  }) async {
    final (operation, arguments) = act.isAddress
        ? (_operationAt(act.name), act.args)
        : await _entityOperation(act);
    return carryOut(
      operation,
      act,
      OperationRun(arguments, screen: screen, held: held, component: component),
    );
  }

  Operation _operationAt(String address) =>
      _ref.read(operationsRegistryProvider)[address] ??
      (throw ImproperAct('There is nothing at "$address"'));

  Future<(Operation, Map<String, Object?>)> _entityOperation(Act act) async {
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
    return (operation, _arguments(entity, action, act));
  }

  /// What [action] binds, its templates read for [entity], and what [act]
  /// says of only what the action lets it say.
  Map<String, Object?> _arguments(Entity entity, EntityAction action, Act act) {
    final scope = {'self': entity.self};
    return {
      for (final MapEntry(:key, :value) in action.bound.entries)
        key: value is String && value.contains('{{')
            ? readTemplate(_ref.read, value, scope)
            : value,
      for (final name in action.args.keys)
        if (act.args.containsKey(name)) name: act.args[name],
    };
  }

  /// Runs [operation] locally. The web editor overrides this to forward
  /// device operations to the TV, as the [act] that asked for them.
  @protected
  Future<String?> carryOut(Operation operation, Act act, OperationRun run) =>
      operation.run(run);
}
