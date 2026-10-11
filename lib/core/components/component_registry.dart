import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/style/style.dart';

/// The primitive components.
enum ComponentRegistry {
  text('Text', 2, 1),
  picture('Picture', 2, 2),
  meter('Meter', 2, 1),

  /// A built-in icon, by name.
  icon('Icon', 1, 1),

  /// A folder's picture, or a preview of its contents.
  folder('Folder picture', 1, 1),

  /// Its behaviour is in its triggers.
  button('Button', 2, 1),

  /// An Android app widget; the `provider` option says which.
  android('App widget', 2, 2);

  const ComponentRegistry(this.label, this.defaultW, this.defaultH);

  final String label;

  /// Default size in cells.
  final int defaultW, defaultH;

  /// Options a new component starts with.
  Map<String, Object?> get starter => switch (this) {
    text => const {'text': '{{clock.time}}'},
    meter => const {'value': '{{clock.second}}', 'max': 60},
    button => const {'label': 'Button'},
    _ => const {},
  };

  /// The settings of this kind; the editor's form is generated from this.
  List<ComponentOption> get options => switch (this) {
    text => [
      const ComponentOption('text', 'Text', OptionKind.template),
      // Only applies with a fixed font size.
      const ComponentOption(
        'overflow',
        'Too long',
        OptionKind.choice,
        usual: 'fade',
        choices: {
          'fade': 'Fades out',
          'ellipsis': 'Cut short with …',
          'clip': 'Cut off',
          'wrap': 'Goes onto more lines',
          'scroll': 'Moves along',
        },
      ),
      ComponentOption(
        'speed',
        'Moves',
        OptionKind.number,
        usual: 40,
        min: 10,
        max: 300,
        step: 10,
        when: (options) => options['overflow'] == 'scroll',
      ),
    ],
    picture => const [
      ComponentOption('source', 'Web address or value', OptionKind.template),
      ComponentOption('alt', 'Says, with no picture', OptionKind.template),
      ComponentOption(
        'fit',
        'Shown',
        OptionKind.choice,
        usual: 'cover',
        choices: {'cover': 'Filling the box', 'contain': 'All of it'},
      ),
    ],
    meter => const [
      ComponentOption('value', 'Value', OptionKind.template),
      // Integers only; scale other values with `| times:`.
      ComponentOption(
        'min',
        'Empty at',
        OptionKind.number,
        usual: 0,
        min: -1000,
        max: 100000,
      ),
      ComponentOption(
        'max',
        'Full at',
        OptionKind.number,
        usual: 100,
        min: -1000,
        max: 100000,
      ),
      ComponentOption(
        'shape',
        'Drawn as',
        OptionKind.choice,
        usual: 'bar',
        choices: {'bar': 'A bar', 'ring': 'A ring'},
      ),
    ],
    button => const [
      ComponentOption('label', 'Says', OptionKind.template),
      ComponentOption('icon', 'Picture', OptionKind.icon),
    ],
    icon => const [
      ComponentOption('icon', 'Which', OptionKind.template),
      ComponentOption(
        'size',
        'Size',
        OptionKind.number,
        min: 8,
        max: 200,
        step: 2,
        unset: 'Fills the box',
      ),
    ],
    folder => const [
      ComponentOption('folder', 'Folder (its id)', OptionKind.template),
    ],
    android => const [],
  };

  /// Style properties specific to this kind, beyond the box ones.
  List<String> get style => switch (this) {
    text => textStyle,
    button => const ['color', 'fontSize'],
    meter || icon => const ['color'],
    picture => const ['radius'],
    folder || android => const [],
  };

  static ComponentRegistry? named(String name) => values.asNameMap()[name];
}
