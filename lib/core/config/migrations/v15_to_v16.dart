import 'package:openlauncher/core/config/migrations/save_json.dart';

/// [act] as it is said now that every action is some entity's.
List<Object?> _owned(Object? act) {
  if (act is! Json) return [act];
  final entity = act['entity'];
  return switch (act['do']) {
    // The quick actions are opened as any folder is: by their variables.
    'menu' => [
      {
        'do': 'set',
        'of': 'quick-actions',
        'var': 'source',
        'value': entity ?? '{{source.id}}',
      },
      {'do': 'set', 'of': 'quick-actions', 'var': 'open', 'value': true},
    ],
    // The launcher's settings are opened by the entity that stands for
    // them.
    'settings' => [
      {'do': 'open', 'entity': 'launcher:settings'},
    ],
    // Taking something off is the layout's to do, told what.
    'remove' => [
      {'do': 'remove', 'what': entity ?? '{{source.id}}'},
    ],
    _ => [act],
  };
}

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json['on'] case final Json on) {
      for (final MapEntry(:key, :value) in on.entries.toList()) {
        if (value is List) on[key] = value.expand(_owned).toList();
      }
    }
    json.values.forEach(_walk);
  }
}

/// No action belongs to nothing: opening the quick actions and the
/// launcher's settings are said with actions entities present, and what
/// is removed is named to the layout. The quick actions say what they are
/// about in a variable of theirs, for what is in them to read.
void actionsOwned(Json save, Device device) {
  _walk(save['layout']);
  _walk(save['prefabs']);
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final panel in panelsOf(layout)) {
    if ((panel['id'], panel['root']) case ('quick-actions', final Json root)) {
      root['vars'] = {
        'source': null,
        if (root['vars'] case final Json vars) ...vars,
      };
    }
  }
}
