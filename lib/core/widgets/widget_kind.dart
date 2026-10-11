import 'package:openlauncher/core/widgets/widget_option.dart';

/// The widgets the launcher can show. A layout item of kind `widget` names
/// one of these in its `ref`.
enum WidgetKind {
  clock('Clock', 2, 1),
  weather('Weather', 2, 1),
  media('Now playing', 2, 1),

  /// The three a widget of the user's own is put together from, in a pane:
  /// each shows what its options say, written as templates
  /// (`{{weather.temperature}}`).
  text('Text', 2, 1),
  picture('Picture', 2, 2),
  meter('Meter', 2, 1),

  /// Something to press: what it does is in the item's triggers.
  button('Button', 2, 1),

  /// A widget provided by an installed app; the item's `provider` option
  /// says which.
  android('App widget', 2, 2);

  const WidgetKind(this.label, this.defaultW, this.defaultH);

  final String label;

  /// The size, in cells, a new widget of this kind starts with.
  final int defaultW, defaultH;

  /// The options a new widget of this kind starts with.
  Map<String, Object?> get starter => switch (this) {
    text => const {'text': '{{time}}'},
    meter => const {'value': '{{time.second}}', 'max': 60},
    button => const {'label': 'Button'},
    _ => const {},
  };

  /// What can be set about a widget of this kind. **A new setting is a
  /// line here and its use where the widget is drawn**: the editor's form
  /// is made from this list.
  List<WidgetOption> get options => switch (this) {
    clock => const [
      WidgetOption('hour24', '24-hour', OptionKind.toggle, usual: true),
      WidgetOption('date', 'Show the date', OptionKind.toggle, usual: true),
      WidgetOption('seconds', 'Show seconds', OptionKind.toggle, usual: false),
    ],
    weather => const [
      WidgetOption('fahrenheit', 'Fahrenheit', OptionKind.toggle, usual: false),
    ],
    text => [
      const WidgetOption('text', 'Text', OptionKind.template),
      const WidgetOption(
        'size',
        'Letter size',
        OptionKind.number,
        min: 8,
        max: 200,
        step: 2,
        unset: 'Fills the box',
      ),
      // Text made to fill the box is never too long for it.
      WidgetOption(
        'overflow',
        'Too long',
        OptionKind.choice,
        usual: 'fade',
        choices: const {
          'fade': 'Fades out',
          'ellipsis': 'Cut short with …',
          'clip': 'Cut off',
          'wrap': 'Goes onto more lines',
          'scroll': 'Moves along',
        },
        when: (options) => options['size'] is num,
      ),
      WidgetOption(
        'speed',
        'Moves',
        OptionKind.number,
        usual: 40,
        min: 10,
        max: 300,
        step: 10,
        when: (options) =>
            options['size'] is num && options['overflow'] == 'scroll',
      ),
      const WidgetOption(
        'align',
        'Sits',
        OptionKind.choice,
        usual: 'center',
        choices: {'left': 'Left', 'center': 'In the middle', 'right': 'Right'},
      ),
      const WidgetOption('bold', 'Bold', OptionKind.toggle, usual: false),
      const WidgetOption('colour', 'Colour', OptionKind.colour),
    ],
    picture => const [
      WidgetOption('source', 'Web address or value', OptionKind.template),
      WidgetOption(
        'fit',
        'Shown',
        OptionKind.choice,
        usual: 'cover',
        choices: {'cover': 'Filling the box', 'contain': 'All of it'},
      ),
      WidgetOption(
        'round',
        'Round corners',
        OptionKind.number,
        usual: 6,
        max: 120,
        step: 2,
      ),
    ],
    meter => const [
      WidgetOption('value', 'Value', OptionKind.template),
      // Whole numbers; a value of another scale is brought to one with
      // `| times:`.
      WidgetOption(
        'min',
        'Empty at',
        OptionKind.number,
        usual: 0,
        min: -1000,
        max: 100000,
      ),
      WidgetOption(
        'max',
        'Full at',
        OptionKind.number,
        usual: 100,
        min: -1000,
        max: 100000,
      ),
      WidgetOption(
        'shape',
        'Drawn as',
        OptionKind.choice,
        usual: 'bar',
        choices: {'bar': 'A bar', 'ring': 'A ring'},
      ),
      WidgetOption('colour', 'Colour', OptionKind.colour),
    ],
    button => const [
      WidgetOption('label', 'Says', OptionKind.template),
      WidgetOption('icon', 'Picture', OptionKind.icon),
      WidgetOption('colour', 'Colour', OptionKind.colour),
    ],
    media || android => const [],
  };

  static WidgetKind? named(String name) => values.asNameMap()[name];
}
