/// What kind of thing a widget's option is, which is what decides how the
/// editor lets it be set.
enum OptionKind {
  /// Text that values can be written into (`{{clock.time}}`).
  template,

  /// Plain text.
  text,
  number,
  toggle,

  /// One of [WidgetOption.choices].
  choice,

  /// A colour, saved as `#RRGGBBAA`.
  colour,

  /// The name of one of the pictures a button can have.
  icon,
}

/// One setting of a widget: where it is kept in the item's options, what
/// it is called, and what it may be. The editor draws its form from these,
/// knowing nothing of the widget.
class WidgetOption {
  const WidgetOption(
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
  });

  final String key, label;
  final OptionKind kind;

  /// What it is while nothing is saved for it; setting it back to this
  /// saves nothing.
  final Object? usual;

  /// For a choice: what is saved, with what each is called.
  final Map<String, String> choices;

  /// For a number.
  final int min, max, step;

  /// For a number that may be left unset, one step below [min]: what that
  /// is called.
  final String? unset;

  /// Says, from the options as they are, whether this one means anything
  /// now; it is offered only when it does.
  final bool Function(Map<String, Object?> options)? when;
}
