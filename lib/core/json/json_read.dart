/// JSON reading helpers. Deliberately not in any barrel.
library;

typedef Json = Map<String, Object?>;

/// [value] as a JSON object, or an empty one when it is not.
Json jsonObject(Object? value) => switch (value) {
  final Json json => json,
  final Map<Object?, Object?> map => map.cast(),
  _ => const {},
};

/// Whether [a] and [b] hold the same JSON, objects compared in any key order.
bool jsonEquals(Object? a, Object? b) => switch ((a, b)) {
  (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
    a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && jsonEquals(a[key], b[key])),
  (final List<Object?> a, final List<Object?> b) =>
    a.length == b.length &&
        Iterable.generate(a.length)
            .every((index) => jsonEquals(a[index], b[index])),
  _ => a == b,
};

T? jsonOptional<T>(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('"$key" has the wrong type');
}

T jsonRequired<T>(Map<Object?, Object?> json, String key) =>
    jsonOptional<T>(json, key) ?? (throw FormatException('"$key" is missing'));

/// Whole numbers are written as ints.
num tidy(double value) =>
    value == value.roundToDouble() ? value.toInt() : value;

double hundredths(double value) => (value * 100).roundToDouble() / 100;

T jsonNamed<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

List<T> jsonList<T>(
  Map<Object?, Object?> json,
  String key,
  T Function(Map<Object?, Object?>) parse,
) => [
  for (final entry in jsonOptional<List<Object?>>(json, key) ?? const [])
    if (entry is Map<Object?, Object?>)
      parse(entry)
    else
      throw FormatException('"$key" must hold objects'),
];
