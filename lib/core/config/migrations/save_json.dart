/// A save, or part of one, as JSON.
typedef Json = Map<String, Object?>;

/// What is known of the device a save is being brought up to date on. With
/// nothing known the rules still do their work, only less well.
class Device {
  const Device({this.names = const {}});

  static const unknown = Device();

  /// What the device calls each card, by card id.
  final Map<String, String> names;
}

/// The parts of [json] under [key] that are objects.
List<Json> objectsIn(Json json, String key) => [
  if (json[key] case final List<Object?> entries)
    for (final entry in entries)
      if (entry is Json) entry,
];

Json? layoutOf(Json save) => switch (save['layout']) {
  final Json layout => layout,
  _ => null,
};

List<Json> panelsOf(Json layout) => objectsIn(layout, 'panels');

List<Json> itemsOf(Json pane) => objectsIn(pane, 'items');

/// [pane] and every pane inside it.
Iterable<Json> panesIn(Json pane) sync* {
  yield pane;
  for (final item in itemsOf(pane)) {
    if (item['pane'] case final Json inner) yield* panesIn(inner);
  }
}

/// Every pane of [layout], each panel's own first.
Iterable<Json> panesOf(Json layout) sync* {
  for (final panel in panelsOf(layout)) {
    if (panel['pane'] case final Json root) yield* panesIn(root);
  }
}

/// The strings in [json], which may be anything.
Iterable<String> stringsIn(Object? json) =>
    json is List<Object?> ? json.whereType<String>() : const [];
