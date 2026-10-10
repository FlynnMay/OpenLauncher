/// Reading and writing the layout's JSON. Not part of the barrel: only the
/// layout model's own files use it.
library;

T? jsonOptional<T>(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('"$key" has the wrong type');
}

T jsonRequired<T>(Map<Object?, Object?> json, String key) =>
    jsonOptional<T>(json, key) ?? (throw FormatException('"$key" is missing'));

/// Whole numbers are written without a fraction, as the page writes them.
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
