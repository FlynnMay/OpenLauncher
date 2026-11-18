/// Rebuilds one entry of a map. [walk] carries on into [value] the way the
/// rest of the tree is walked.
typedef EntryWalker = Object? Function(
  String key,
  Object? value,
  Object? Function(Object?) walk,
);

Object? _walkEntry(String key, Object? value, Object? Function(Object?) walk) =>
    walk(value);

/// [json] rebuilt with every text in it replaced by what [onText] makes of
/// it. Each entry of a map passes through [onEntry] first, which can give
/// its value another treatment.
Object? walkJson(
  Object? json, {
  required Object? Function(String text) onText,
  EntryWalker onEntry = _walkEntry,
}) {
  Object? walk(Object? value) => switch (value) {
    final String text => onText(text),
    final List<Object?> list => [for (final item in list) walk(item)],
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String) key: onEntry(key, value, walk),
    },
    _ => value,
  };
  return walk(json);
}
