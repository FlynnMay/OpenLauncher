import 'package:openlauncher/core/config/migrations/save_json.dart';

/// Visibility is a module every node has: a node's `hidden: true` is
/// `visibility.visible: false` (in a node, an override, a prefab rule, a
/// variant), and Sizing's `keep` is Visibility's.
void visibilityAsModule(Json save, Device device) {
  void walk(Object? json) {
    switch (json) {
      case final Json map:
        _convert(map);
        map.values.forEach(walk);
      case final List<Object?> list:
        list.forEach(walk);
    }
  }

  walk(save['layout']);
  walk(save['prefabs']);
}

void _convert(Json node) {
  final hidden = node.remove('hidden');
  final modules = node['modules'];
  final keep = modules is Json && modules['sizing'] is Json
      ? (modules['sizing']! as Json).remove('keep')
      : null;
  final hide = hidden == true;
  if (!hide && keep == null) return;
  final into = node['modules'] is Json
      ? node['modules']! as Json
      : (node['modules'] = <String, Object?>{});
  final values = into['visibility'] is Json
      ? into['visibility']! as Json
      : (into['visibility'] = <String, Object?>{});
  if (hide) values['visible'] = false;
  if (keep is bool) values['keep'] = keep;
}
