import 'package:openlauncher/core/config/migrations/save_json.dart';

// The two prefabs there were when this step was written, and where an
// instance and a pane keep what they say of them.
const _prefabs = ['app-card', 'folder-card'];

/// The object under [key], there to be added to: a copy of what is there,
/// which may be something that cannot be changed, or a new one.
Json _map(Json json, String key) {
  final map = <String, Object?>{
    if (json[key] case final Map<Object?, Object?> there) ...there.cast(),
  };
  json[key] = map;
  return map;
}

/// A card's own `hideName` and `look` become what it sets differently from
/// its prefab: the `name` part hidden, the `row` layout. There is one way
/// to say each, where for a while there were two.
void cardLooksAsOverrides(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      final hidden = item.remove('hideName') == true;
      final row = item.remove('look') == 'row';
      if (!hidden && !row) continue;
      final options = _map(item, 'options');
      if (row) options['layout'] = 'row';
      if (hidden) _map(_map(options, 'parts'), 'name')['hidden'] = true;
    }
  }
}

/// What a pane made of every card in it, `itemLook` and `itemNames`,
/// becomes a rule for each prefab: the layout its instances use, and
/// whether their name shows.
void paneLooksAsRules(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    final look = pane.remove('itemLook');
    final names = pane.remove('itemNames');
    if (look is! String && names is! bool) continue;
    final rules = _map(pane, 'rules');
    for (final prefab in _prefabs) {
      final rule = _map(rules, prefab);
      if (look is String) rule['layout'] = look == 'row' ? 'row' : 'stacked';
      if (names is bool) {
        _map(_map(rule, 'parts'), 'name')['hidden'] = !names;
      }
    }
  }
}
