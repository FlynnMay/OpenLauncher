/// The type of an option; decides which editor field it gets.
enum FieldKind {
  /// Text that may contain `{{...}}`.
  template,

  text,
  number,
  toggle,

  /// One of [Field.choices].
  choice,

  /// `#RRGGBBAA`.
  colour,

  /// A pack icon's name (`set:name`), or a template that reads as one.
  icon,

  /// A colour, or a gradient (`colors`, `stops`, `angle`).
  fill,

  /// One radius or four.
  corners,

  /// Free text parsed by [typedValue].
  value,

  /// A repeating group of [Field.fields].
  list,

  /// Fields kept together under one name, laid out in columns; the value is
  /// a map of theirs. See [Field.group].
  group,
}

/// How a choice is drawn. The first three pick one; the last three pick
/// several.
enum ChoiceLook { dropdown, radio, segmented, checks, chips, multiDropdown }

/// When a choice that asks the web does so.
enum FindOn {
  /// Asked once, then filtered here as the user types.
  filter,

  /// Asked as the user types, after a pause.
  type,

  /// Asked when the user presses Enter.
  enter,
}

/// How a choice finds its options by asking.
class FieldFinding {
  const FieldFinding({
    required this.on,
    required this.debounce,
    required this.minChars,
  });

  final FindOn on;
  final Duration debounce;
  final int minChars;
}

/// What a secret field can say and do; the secret itself is never here.
/// [replace] gets a value of the field's own kind.
class FieldSecret {
  const FieldSecret({
    required this.isSet,
    required this.replace,
    required this.clear,
  });

  final bool isSet;
  final Future<void> Function(Object value) replace;
  final Future<void> Function() clear;
}

/// One option a search found: how it is listed, under which heading, and
/// the value choosing it keeps.
typedef FieldHit = ({String title, String group, Object? value});

/// Parses [text] as null, a number, a bool, or leaves it as text.
Object? typedValue(String text) => switch (text.trim()) {
  '' => null,
  'true' => true,
  'false' => false,
  final said => num.tryParse(said) ?? said,
};

/// One setting, described as data: its key, label and type. Editor forms are
/// generated from these.
class Field {
  const Field(
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
    this.find,
    this.secret,
    this.placeholder = '',
    this.multiline = false,
    this.help = '',
    this.fits,
    this.look,
    this.multiple = false,
    this.remote,
    this.maxChoices,
    this.whenRoot,
    this.group = const [],
    this.columns = 1,
    this.span = 1,
  });

  final String key, label;
  final FieldKind kind;

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

  /// The same, given the form's whole value too; used before [when].
  final bool Function(Map<String, Object?> values, Map<String, Object?> root)?
  whenRoot;

  /// For a group: its fields, the units its rows are wide, and for any field
  /// the units of its group's row it takes.
  final List<Field> group;
  final int columns, span;

  /// For a list: the fields of one entry. [label] is the add button's text.
  final List<Field> Function(Map<String, Object?> one)? fields;

  /// For a list: a new entry's values.
  final Map<String, Object?> blank;

  /// For a list: the field shown as each entry's heading, and the prompt for
  /// it when adding.
  final String? heading, asks;

  /// For a choice from the web: what typed text finds.
  final Future<List<FieldHit>> Function(String text)? find;

  /// When given, the field is a secret of its own kind: whether it is set,
  /// and how to replace or clear it.
  final FieldSecret? secret;

  /// For text: the hint, whether it has several lines, and whether a typed
  /// text is acceptable (a text that is not is shown as such, not kept).
  final String placeholder;
  final bool multiline;
  final bool Function(String text)? fits;

  /// Shown under the field.
  final String help;

  /// For a choice: how it is drawn, null to pick by the number of options;
  /// whether several may be chosen (the value is then a list); how many at
  /// most; and how a choice from the web asks.
  final ChoiceLook? look;
  final bool multiple;
  final int? maxChoices;
  final FieldFinding? remote;
}

/// [choices] each labelled with its own value.
Map<String, String> labelledAsThemselves(Iterable<String> choices) => {
  for (final choice in choices) choice: choice,
};

/// The editor's fields for [args], what an act may say: an action's, or an
/// operation's. Each key starts with [keyPrefix]; an argument without
/// choices gets a [free] field.
List<Field> argFields(
  Map<String, List<String>> args, {
  String keyPrefix = '',
  FieldKind free = FieldKind.value,
  String? unset,
}) => [
  for (final MapEntry(key: name, value: choices) in args.entries)
    choices.isEmpty
        ? Field(
            '$keyPrefix$name',
            name == 'of' ? 'of (component ID)' : name,
            free,
          )
        : Field(
            '$keyPrefix$name',
            name,
            FieldKind.choice,
            unset: unset,
            choices: labelledAsThemselves(choices),
          ),
];
