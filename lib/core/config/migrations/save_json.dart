import 'package:openlauncher/core/json/json_read.dart';

export 'package:openlauncher/core/json/json_read.dart'
    show Json, jsonEquals, jsonObject;

class Device {
  const Device({this.names = const {}});

  static const unknown = Device();

  /// By entity id.
  final Map<String, String> names;
}

List<Json> objectsIn(Json json, String key) => [
  if (json[key] case final List<Object?> entries)
    for (final entry in entries)
      if (entry is Json) entry,
];

Json? layoutOf(Json save) => switch (save['layout']) {
  final Json layout => layout,
  _ => null,
};

Iterable<Json> layerRoots(Json save) => [
  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers'))
    if (layer['root'] case final Json root) root,
];

Iterable<Json> prefabRoots(Json save) => [
  for (final prefab in objectsIn(save, 'prefabs'))
    if (prefab['root'] case final Json root) root,
];

const slotLayoutModules = {'layout', 'scroll', 'prefabRules'};

Iterable<String> stringsIn(Object? json) =>
    json is List<Object?> ? json.whereType<String>() : const [];

Json without(Json json, Set<String> keys) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!keys.contains(key)) key: value,
};
