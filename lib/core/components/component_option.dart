/// The type of an option; decides which editor field it gets.
enum OptionKind {
  /// Text that may contain `{{...}}`.
  template,

  text,
  number,
  toggle,

  /// One of [ComponentOption.choices].
  choice,

  /// `#RRGGBBAA`.
  colour,

  /// A built-in icon name.
  icon,

  /// A colour, or a gradient (`colors`, `stops`, `angle`).
  fill,

  /// One radius or four.
  corners,

  /// Free text parsed by [typedValue].
  value,

  /// A repeating group of [ComponentOption.fields].
  list,
}

/// Parses [text] as null, a number, a bool, or leaves it as text.
Object? typedValue(String text) => switch (text.trim()) {
  '' => null,
  'true' => true,
  'false' => false,
  final said => num.tryParse(said) ?? said,
};

/// One setting, described as data: its key, label and type. Editor forms are
/// generated from these.
class ComponentOption {
  const ComponentOption(
    this.key,
    this.label,
    this.kind, {
    this.defaultValue,
    this.choices = const {},
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.decimal = false,
    this.unset,
    this.when,
    this.fields,
    this.blank = const {},
    this.heading,
    this.asks,
  });

  final String key, label;
  final OptionKind kind;

  /// The default; not saved.
  final Object? defaultValue;

  /// Choice values with their labels.
  final Map<String, String> choices;

  /// For numbers; for a list, [max] is the most entries.
  final int min, max, step;

  /// For a number: whether it may have a fraction.
  final bool decimal;

  /// Label for "unset", for a number or choice that allows it.
  final String? unset;

  /// Whether the option applies, given the current values.
  final bool Function(Map<String, Object?> options)? when;

  /// For a list: the fields of one entry. [label] is the add button's text.
  final List<ComponentOption> Function(Map<String, Object?> one)? fields;

  /// For a list: a new entry's values.
  final Map<String, Object?> blank;

  /// For a list: the field shown as each entry's heading, and the prompt for
  /// it when adding.
  final String? heading, asks;
}
