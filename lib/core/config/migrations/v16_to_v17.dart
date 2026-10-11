import 'package:openlauncher/core/config/migrations/save_json.dart';

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json['vars'] case final Json vars when vars.containsKey('source')) {
      final was = vars['source'];
      // Already in long form.
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

/// Variables named `source` become entity-typed.
void variablesTyped(Json save, Device device) {
  _walk(save['layout']);
  _walk(save['prefabs']);
}
