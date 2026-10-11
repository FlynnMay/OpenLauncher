import 'package:openlauncher/core/config/migrations/save_json.dart';

/// [act] rewritten so an entity owns it.
List<Object?> _owned(Object? act) {
  if (act is! Json) return [act];
  final entity = act['entity'];
  return switch (act['do']) {
    // `menu` becomes two `set`s on the quick-actions pane.
    'menu' => [
      {
        'do': 'set',
        'of': 'quick-actions',
        'var': 'source',
        'value': entity ?? '{{source.id}}',
      },
      {'do': 'set', 'of': 'quick-actions', 'var': 'open', 'value': true},
    ],
    'settings' => [
      {'do': 'open', 'entity': 'launcher:settings'},
    ],
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

/// Rewrites the removed `menu` and `settings` actions, gives `remove` its
/// target, and declares `source` on the quick-actions pane.
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
