import 'package:openlauncher/core/config/migrations/save_json.dart';

const _goneOperations = {'forceStopApp', 'runSetup', 'setHomeButton'};

/// Force stop and automatic setup went with the launcher's ADB client: acts
/// that asked for them are dropped, and a button left with none goes too.
/// Switching the Home button becomes changing that permission.
void withoutAdbActions(Json save, Device device) {
  final own = <Object?>{};
  // The user's own actions that ran them, as `<entity> <action>`.
  final gone = <String>{};
  for (final entity in objectsIn(save, 'entities')) {
    own.add(entity['id']);
    if (entity['actions'] case final Json actions) {
      actions.removeWhere((name, action) {
        final ran = action is Json && _goneOperations.contains(action['run']);
        if (ran) gone.add('${entity['id']} $name');
        return ran;
      });
    }
  }

  bool isGone(Object? act) {
    if (act is! Json) return false;
    final name = act['do'], entity = act['entity'];
    if (gone.contains('$entity $name')) return true;
    if (own.contains(entity)) return false;
    return name == 'forceStop' || (entity == 'system' && name == 'setup');
  }

  /// Whether [json] is a button this leaves with nothing to do.
  bool emptied(Object? json) {
    if (json is List<Object?>) {
      json.removeWhere(emptied);
      return false;
    }
    if (json is! Json) return false;
    json.values.forEach(emptied);
    final on = json['on'];
    if (on is! Json) return false;
    var dropped = false;
    for (final acts in on.values.whereType<List<Object?>>()) {
      final before = acts.length;
      acts.removeWhere(isGone);
      dropped |= acts.length != before;
      for (final act in acts) {
        if (act case {'do': 'homeButton', 'entity': 'system'}) {
          act
            ..['do'] = 'access'
            ..['access'] = 'homeButton'
            ..remove('enabled');
        }
      }
    }
    return dropped &&
        json['kind'] == 'button' &&
        on.values.every((acts) => acts is List && acts.isEmpty);
  }

  emptied(save);
}
