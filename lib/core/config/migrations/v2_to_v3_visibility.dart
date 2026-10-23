import 'package:openlauncher/core/config/migrations/save_json.dart';

/// Visibility is a module every node has: a node's `hidden: true` is
/// `visibility.visible: false` (in a node, an override, a prefab rule, a
/// variant), and Sizing's `keep` is Visibility's.
void visibilityAsModule(Json save, Device device) {
  _visibilityAsModuleIn(save['layout']);
  _visibilityAsModuleIn(save['prefabs']);
}

void _visibilityAsModuleIn(Object? json) {
  switch (json) {
    case final Json object:
      _hiddenAsVisibility(object);
      object.values.forEach(_visibilityAsModuleIn);
    case final List<Object?> list:
      list.forEach(_visibilityAsModuleIn);
  }
}

/// [node]'s `hidden` and its Sizing's `keep` moved to its Visibility.
void _hiddenAsVisibility(Json node) {
  final hidden = node.remove('hidden') == true;
  final keep = switch (node['modules']) {
    {'sizing': final Json sizing} => sizing.remove('keep'),
    _ => null,
  };
  if (!hidden && keep == null) return;
  final visibility = _objectAt(_objectAt(node, 'modules'), 'visibility');
  if (hidden) visibility['visible'] = false;
  if (keep is bool) visibility['keep'] = keep;
}

/// The object at [key] in [json], made there if it holds none.
Json _objectAt(Json json, String key) => switch (json[key]) {
  final Json object => object,
  _ => json[key] = <String, Object?>{},
};
