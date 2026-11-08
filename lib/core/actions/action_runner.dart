import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/core/sources/source_request.dart';
import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher_domain/actions/act.dart';

class ImproperAct extends FormatException {
  const ImproperAct(super.message);
}

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

/// An address is checked as it runs.
bool isProper(Act act, Iterable<Entity> entities) {
  if (act.isAddress) return true;
  try {
    targetOf(act, entities);
    return true;
  } on ImproperAct {
    return false;
  }
}

/// Every entity's, first of each name, when [target] is known only as it runs.
Map<String, EntityAction> actionsOf(String? target, Iterable<Entity> entities) {
  if (entities.byId(target) case final entity?) return entity.actions;
  final everyAction = entities.expand((entity) => entity.actions.entries);
  final firstOfEach = <String, EntityAction>{};
  for (final MapEntry(key: name, value: action) in everyAction) {
    firstOfEach.putIfAbsent(name, () => action);
  }
  return firstOfEach;
}

/// Keeps only the arguments [action] lets an act add.
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

  /// Returns a message for the user, or null. Throws [ImproperAct] if [act]
  /// cannot be done as written.
  Future<String?> run(
    Act act, {
    ActionScreen? screen,
    bool held = false,
    String? component,
  }) async {
    final (operation, arguments, entityId, then) = act.isAddress
        ? (_operationAt(act.name), _withUrl(act.name, act.args), null, null)
        : await _entityOperation(act);
    return carryOut(
      operation,
      act,
      OperationRun(
        arguments,
        screen: screen,
        held: held,
        component: component,
        entityId: entityId,
        then: then,
      ),
    );
  }

  Operation _operationAt(String address) =>
      _ref.read(operationsRegistryProvider)[address] ??
      (throw ImproperAct('There is nothing at "$address"'));

  Future<(Operation, Map<String, Object?>, String, String?)> _entityOperation(
    Act act,
  ) async {
    await _ref.read(configProvider.future);
    final (:entity, :action) = targetOf(
      act,
      await _ref.read(entitiesProvider.future),
    );
    final scope = {
      'self': entity.self,
      'settings': plainSettingsOf(_ref, HttpService.packOf(entity.id)),
    };
    final address = '${_filled(action.run, scope)}';
    final operation = _ref.read(operationsRegistryProvider)[address];
    if (operation == null) {
      throw ImproperAct(
        '"${act.name}" of ${entity.label} runs "$address", '
        'which there is none of',
      );
    }
    return (
      operation,
      _withUrl(address, _arguments(action, act, scope)),
      entity.id,
      action.then,
    );
  }

  /// A web address is the `url` of the request it makes.
  Map<String, Object?> _withUrl(String address, Map<String, Object?> args) =>
      isWebAddress(address) ? {...args, 'url': address} : args;

  Map<String, Object?> _arguments(
    EntityAction action,
    Act act,
    Map<String, Object?> scope,
  ) {
    return {
      for (final MapEntry(:key, :value) in action.bound.entries)
        key: _filled(value, scope),
      for (final name in action.args.keys)
        if (act.args.containsKey(name)) name: act.args[name],
    };
  }

  /// [value] with every template in it filled, however deep.
  Object? _filled(Object? value, Map<String, Object?> scope) => switch (value) {
    final String text when text.contains('{{') => readTemplate(
      _ref.read,
      text,
      scope,
    ),
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        key: _filled(value, scope),
    },
    final List<Object?> list => [for (final item in list) _filled(item, scope)],
    _ => value,
  };

  /// Runs [operation] locally. The web editor overrides this to forward
  /// device operations to the TV, as the [act] that asked for them.
  @protected
  Future<String?> carryOut(
    Operation operation,
    Act act,
    OperationRun run,
  ) async {
    final message = await operation.run(run);
    await _fetchAgain(run);
    return message;
  }

  Future<void> _fetchAgain(OperationRun run) async {
    final pack = HttpService.packOf(run.entityId);
    if (pack != null && run.then != null) {
      await fetchSourceAgain(_ref, pack, run.then!);
    }
  }
}
