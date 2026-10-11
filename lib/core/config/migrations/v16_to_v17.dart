import 'package:openlauncher/core/config/migrations/save_json.dart';

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json['vars'] case final Json vars when vars.containsKey('source')) {
      final was = vars['source'];
      // Said in full already, with or without what sort it is.
      if (was is Json &&
          (was.containsKey('value') || was.containsKey('when'))) {
        was.putIfAbsent('type', () => 'entity');
      } else {
        vars['source'] = {'value': was, 'type': 'entity'};
      }
    }
    json.values.forEach(_walk);
  }
}

/// A variable says what sort of thing it holds. One that named an entity
/// stood for it only because what it held happened to be an id; now it
/// says it holds one. Those there were are the ones the launcher's own
/// prefabs are handed an entity as, called `source`.
void variablesTyped(Json save, Device device) {
  _walk(save['layout']);
  _walk(save['prefabs']);
}
