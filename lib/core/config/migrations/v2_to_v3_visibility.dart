import 'package:openlauncher/core/config/migrations/save_json.dart';

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

Json _objectAt(Json json, String key) => switch (json[key]) {
  final Json object => object,
  _ => json[key] = <String, Object?>{},
};
