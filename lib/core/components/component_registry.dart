import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/style/style.dart';

/// The primitive components.
enum ComponentRegistry {
  text('Text', 2, 1),
  picture('Picture', 2, 2),
  meter('Meter', 2, 1),

  /// A pack's icon, by name.
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
        'Overflow',
        OptionKind.choice,
        defaultValue: 'fade',
        choices: {
          'fade': 'Fade',
          'ellipsis': 'Ellipsis',
          'clip': 'Clip',
          'wrap': 'Wrap',
          'scroll': 'Scroll',
        },
      ),
      ComponentOption(
        'speed',
        'Scroll speed',
        OptionKind.number,
        defaultValue: 40,
        min: 10,
        max: 300,
        step: 10,
        when: (options) => options['overflow'] == 'scroll',
      ),
    ],
    picture => const [
      ComponentOption('source', 'Source (URL or value)', OptionKind.template),
      ComponentOption('alt', 'Alt text', OptionKind.template),
      ComponentOption(
        'fit',
        'Fit',
        OptionKind.choice,
        defaultValue: 'cover',
        choices: {'cover': 'Cover', 'contain': 'Contain'},
      ),
    ],
    meter => const [
      ComponentOption('value', 'Value', OptionKind.template),
      // Integers only; scale other values with `| times:`.
      ComponentOption(
        'min',
        'Min',
        OptionKind.number,
        defaultValue: 0,
        min: -1000,
        max: 100000,
      ),
      ComponentOption(
        'max',
        'Max',
        OptionKind.number,
        defaultValue: 100,
        min: -1000,
        max: 100000,
      ),
      ComponentOption(
        'shape',
        'Shape',
        OptionKind.choice,
        defaultValue: 'bar',
        choices: {'bar': 'Bar', 'ring': 'Ring'},
      ),
    ],
    button => const [
      ComponentOption('label', 'Label', OptionKind.template),
      ComponentOption('icon', 'Icon', OptionKind.icon),
    ],
    icon => const [
      ComponentOption('icon', 'Icon', OptionKind.icon),
      ComponentOption(
        'size',
        'Size',
        OptionKind.number,
        min: 8,
        max: 200,
        step: 2,
        unset: 'Auto',
      ),
    ],
    folder => const [
      ComponentOption('folder', 'Folder ID', OptionKind.template),
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
