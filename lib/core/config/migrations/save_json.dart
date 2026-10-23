import 'package:openlauncher/core/json/json_read.dart';

export 'package:openlauncher/core/json/json_read.dart' show Json, jsonObject;

/// Device info available to a migration; may be empty.
class Device {
  const Device({this.names = const {}});

  static const unknown = Device();

  /// Entity id -> the device's name for it.
  final Map<String, String> names;
}

/// The objects in the list at [key].
List<Json> objectsIn(Json json, String key) => [
  if (json[key] case final List<Object?> entries)
    for (final entry in entries)
      if (entry is Json) entry,
];

Json? layoutOf(Json save) => switch (save['layout']) {
  final Json layout => layout,
  _ => null,
};

Iterable<String> stringsIn(Object? json) =>
    json is List<Object?> ? json.whereType<String>() : const [];

/// [json] less [keys].
Json without(Json json, Set<String> keys) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!keys.contains(key)) key: value,
};
