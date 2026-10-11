/// What kind of thing a component's option is, which is what decides how the
/// editor lets it be set.
enum OptionKind {
  /// Text that values can be written into (`{{clock.time}}`).
  template,

  /// Plain text.
  text,
  number,
  toggle,

  /// One of [ComponentOption.choices].
  choice,

  /// A colour, saved as `#RRGGBBAA`.
  colour,

  /// The name of one of the pictures a button can have.
  icon,

  /// What a box is filled with: one colour as `#RRGGBBAA`, or a gradient
  /// as its `colors`, their `stops` and its `angle`.
  fill,

  /// How round a box's corners are: one number for all four, or four.
  corners,

  /// Anything, typed as text: kept as a number or as true or false where
  /// it reads as one ([typedValue]).
  value,

  /// Several things with the same settings, [ComponentOption.fields], one
  /// after another: added to, taken from, each set like any other.
  list,
}

/// What [text] says: nothing, a number, true or false, or the text it is.
Object? typedValue(String text) => switch (text.trim()) {
  '' => null,
  'true' => true,
  'false' => false,
  final said => num.tryParse(said) ?? said,
};

/// One setting of a component: where it is kept in the item's options, what
/// it is called, and what it may be. The editor draws its form from these,
/// knowing nothing of the component.
class ComponentOption {
  const ComponentOption(
    this.key,
    this.label,
    this.kind, {
    this.usual,
    this.choices = const {},
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.unset,
    this.when,
    this.fields,
    this.blank = const {},
    this.heading,
    this.asks,
  });

  final String key, label;
  final OptionKind kind;

  /// What it is while nothing is saved for it; setting it back to this
  /// saves nothing.
  final Object? usual;

  /// For a choice: what is saved, with what each is called.
  final Map<String, String> choices;

  /// For a number; for a list, [max] is the most there can be in it.
  final int min, max, step;

  /// For a number that may be left unset, one step below [min], and a
  /// choice that may be left unmade: what that is called.
  final String? unset;

  /// Says, from the options as they are, whether this one means anything
  /// now; it is offered only when it does.
  final bool Function(Map<String, Object?> options)? when;

  /// For a list: the settings of one of the things in it, which may go by
  /// what that one is set to. [label] is what adding one is called.
  final List<ComponentOption> Function(Map<String, Object?> one)? fields;

  /// For a list: what a new one starts as.
  final Map<String, Object?> blank;

  /// For a list: which of a thing's values it is headed by, where it is
  /// headed by one; and, where a new one is asked its heading first, what
  /// that question is called.
  final String? heading, asks;
}
