import 'package:openlauncher/core/config/migrations/save_json.dart';

const _goneOperations = {'forceStopApp', 'runSetup', 'setHomeButton'};

void withoutAdbActions(Json save, Device device) =>
    _GoneActs(objectsIn(save, 'entities')).dropFrom(save);

class _GoneActs {
  _GoneActs(List<Json> entities) {
    entities.forEach(_dropGoneActions);
  }

  final _ownEntities = <Object?>{};

  final _goneActionKeys = <String>{};

  static String _actionKey(Object? entity, Object? action) => '$entity $action';

  void _dropGoneActions(Json entity) {
    _ownEntities.add(entity['id']);
    if (entity['actions'] case final Json actions) {
      actions.removeWhere((name, action) {
        final ranGone =
            action is Json && _goneOperations.contains(action['run']);
        if (ranGone) _goneActionKeys.add(_actionKey(entity['id'], name));
        return ranGone;
      });
    }
  }

  bool _isGone(Object? act) {
    if (act is! Json) return false;
    final name = act['do'];
    final entity = act['entity'];
    if (_goneActionKeys.contains(_actionKey(entity, name))) return true;
    if (_ownEntities.contains(entity)) return false;
    return name == 'forceStop' || (entity == 'system' && name == 'setup');
  }

  /// Returns whether [json] is a button left with nothing to do.
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
      dropped |= _tidied(acts);
    }
    return dropped &&
        json['kind'] == 'button' &&
        triggers.values.every((acts) => acts is List && acts.isEmpty);
  }

  /// Returns whether any act went.
  bool _tidied(List<Object?> acts) {
    final before = acts.length;
    acts
      ..removeWhere(_isGone)
      ..forEach(_homeButtonAsAccess);
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
