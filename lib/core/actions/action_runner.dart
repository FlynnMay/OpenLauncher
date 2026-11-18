import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher_domain/actions/act.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/values/template_fill.dart';

class ImproperAct extends FormatException {
  const ImproperAct(super.message);
}

/// Throws [ImproperAct] if there is none.
({Node node, EntityAction action}) targetOf(Act act, Iterable<Node> nodes) {
  final id = act.arg(entityArg);
  if (id == null || id.isEmpty) {
    throw ImproperAct('"${act.name}" names no entity');
  }
  final node = nodes.where((one) => one.id == id).firstOrNull;
  if (node == null) throw ImproperAct('There is no entity "$id"');
  final action = node.actions[act.name];
  if (action == null) {
    throw ImproperAct('${node.name} has no "${act.name}"');
  }
  return (node: node, action: action);
}

/// An address is checked as it runs.
bool isProper(Act act, Iterable<Node> nodes) {
  if (act.isAddress) return true;
  try {
    targetOf(act, nodes);
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
    final (operation, arguments, entityId, followUps) = act.isAddress
        ? (
            _operationAt(act.name),
            _withUrl(act.name, act.args),
            act.arg(entityArg),
            const <FollowUp>[],
          )
        : await _entityOperation(act, component);
    return carryOut(
      operation,
      act,
      OperationRun(
        arguments,
        screen: screen,
        held: held,
        component: component,
        entityId: entityId,
        followUps: followUps,
      ),
    );
  }

  Operation _operationAt(String address) =>
      _ref.read(operationsRegistryProvider)[address] ??
      (throw ImproperAct('There is nothing at "$address"'));

  Future<(Operation, Map<String, Object?>, String, List<FollowUp>)>
  _entityOperation(Act act, String? caller) async {
    await _ref.read(configProvider.future);
    final (:node, :action) = targetOf(
      act,
      await _ref.read(nodesProvider.future),
    );
    _requireOpenTo(act, node, action, caller);
    final scope = {
      'self': node.self,
      'settings': plainSettingsOf(_ref, HttpService.packOf(node.id)),
    };
    final address = '${_filled(action.run, scope)}';
    final operation = _ref.read(operationsRegistryProvider)[address];
    if (operation == null) {
      throw ImproperAct(
        '"${act.name}" of ${node.name} runs "$address", '
        'which there is none of',
      );
    }
    return (
      operation,
      _withUrl(address, _arguments(action, act, scope)),
      node.id,
      [
        for (final next in action.then)
          (
            address: '${_filled(next.run, scope)}',
            args: _withUrl('${_filled(next.run, scope)}', {
              for (final MapEntry(:key, :value) in next.bound.entries)
                key: _filled(value, scope),
            }),
          ),
      ],
    );
  }

  /// An action a node keeps private or protected is for that node and what
  /// is under it; one asked from outside, such as the web, is declined.
  void _requireOpenTo(Act act, Node node, EntityAction action, String? caller) {
    final within =
        caller != null &&
        (caller == node.id || caller.startsWith('${node.id}/'));
    final open = switch (action.access) {
      NodeAccess.public => true,
      NodeAccess.protected => within,
      NodeAccess.private => caller == node.id,
    };
    if (!open) {
      throw ImproperAct('"${act.name}" of ${node.name} is not open to this');
    }
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
  Object? _filled(Object? value, Map<String, Object?> scope) => fillTemplates(
    value,
    (template) => readTemplate(_ref.read, template, scope),
  );

  /// Runs [operation] locally. The web editor overrides this to forward
  /// device operations to the TV, as the [act] that asked for them.
  @protected
  Future<String?> carryOut(
    Operation operation,
    Act act,
    OperationRun run,
  ) async {
    final message = await operation.run(run);
    for (final next in run.followUps) {
      await _followUp(next, run.entityId);
    }
    return message;
  }

  /// Runs what comes after an action, through [carryOut] again so the web
  /// editor still sends the TV's work to the TV.
  Future<void> _followUp(FollowUp next, String? entityId) {
    final operation = _operationAt(next.address);
    return carryOut(
      operation,
      Act(next.address, {...next.args, entityArg: ?entityId}),
      OperationRun(next.args, entityId: entityId),
    );
  }
}
