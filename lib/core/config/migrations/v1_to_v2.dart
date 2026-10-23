import 'package:openlauncher/core/config/migrations/save_json.dart';

const _goneOperations = {'forceStopApp', 'runSetup', 'setHomeButton'};

/// Force stop and automatic setup went with the launcher's ADB client: acts
/// that asked for them are dropped, and a button left with none goes too.
/// Switching the Home button becomes changing that permission.
void withoutAdbActions(Json save, Device device) =>
    _GoneActs(objectsIn(save, 'entities')).dropFrom(save);

/// Drops the acts that asked for what went with the ADB client.
class _GoneActs {
  _GoneActs(List<Json> entities) {
    entities.forEach(_dropGoneActions);
  }

  final _ownEntities = <Object?>{};

  /// The user's own actions that ran a gone operation, as
  /// `<entity> <action>`.
  final _goneActions = <String>{};

  void _dropGoneActions(Json entity) {
    _ownEntities.add(entity['id']);
    if (entity['actions'] case final Json actions) {
      actions.removeWhere((name, action) {
        final ranGone =
            action is Json && _goneOperations.contains(action['run']);
        if (ranGone) _goneActions.add('${entity['id']} $name');
        return ranGone;
      });
    }
  }

  bool _isGone(Object? act) {
    if (act is! Json) return false;
    final name = act['do'];
    final entity = act['entity'];
    if (_goneActions.contains('$entity $name')) return true;
    if (_ownEntities.contains(entity)) return false;
    return name == 'forceStop' || (entity == 'system' && name == 'setup');
  }

  /// Drops gone acts throughout [json]; whether it is a button this leaves
  /// with nothing to do.
  bool dropFrom(Object? json) {
    if (json is List<Object?>) {
      json.removeWhere(dropFrom);
      return false;
    }
    if (json is! Json) return false;
    json.values.forEach(dropFrom);
    final triggers = json['on'];
    if (triggers is! Json) return false;
    var dropped = false;
    for (final acts in triggers.values.whereType<List<Object?>>()) {
      dropped |= _dropGoneFrom(acts);
      acts.forEach(_homeButtonAsAccess);
    }
    return dropped &&
        json['kind'] == 'button' &&
        triggers.values.every((acts) => acts is List && acts.isEmpty);
  }

  /// Whether any of [acts] went.
  bool _dropGoneFrom(List<Object?> acts) {
    final before = acts.length;
    acts.removeWhere(_isGone);
    return acts.length != before;
  }
}

void _homeButtonAsAccess(Object? act) {
  if (act case {'do': 'homeButton', 'entity': 'system'} && final Json call) {
    call
      ..['do'] = 'access'
      ..['access'] = 'homeButton'
      ..remove('enabled');
  }
}
