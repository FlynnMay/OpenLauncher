import 'package:openlauncher/core/variables/scope.dart';
import 'package:openlauncher/core/widgets/widget_option.dart';

/// The look of a component as it is saved: what it sets, by the name of
/// the property. Anything on the screen may have one; which properties
/// mean something to it is for it to say ([boxStyle], [textStyle], a
/// widget kind's own).
typedef Style = Map<String, Object?>;

/// One property of a look, described once. The editor draws its field from
/// this, knowing nothing of what takes it.
class StyleProp extends WidgetOption {
  const StyleProp(
    super.key,
    super.label,
    super.kind, {
    this.inherits = false,
    super.usual,
    super.choices,
    super.min,
    super.max,
    super.step,
    super.unset = 'Usual',
  });

  /// True for a property that what is inside a component takes after it
  /// in, unless it sets its own: a pane's letters colour is that of every
  /// text in it.
  final bool inherits;
}

/// Every property a look can have. **A new one is a line here, its name in
/// the list of whatever takes it, and its use where that is drawn.**
const styleProps = [
  StyleProp('background', 'Background', OptionKind.fill),
  StyleProp('borderColor', 'Border', OptionKind.colour),
  StyleProp(
    'borderWidth',
    'Border width',
    OptionKind.number,
    usual: 2,
    max: 20,
    unset: null,
  ),
  StyleProp('radius', 'Corners', OptionKind.corners, max: 120, step: 2),
  StyleProp('padding', 'Padding', OptionKind.number, max: 80, step: 2),
  StyleProp(
    'opacity',
    'Opacity %',
    OptionKind.number,
    usual: 100,
    max: 100,
    step: 5,
    unset: null,
  ),
  StyleProp(
    'shadow',
    'Shadow',
    OptionKind.number,
    usual: 0,
    max: 60,
    step: 2,
    unset: null,
  ),
  StyleProp('color', 'Colour', OptionKind.colour, inherits: true),
  StyleProp(
    'fontSize',
    'Letter size',
    OptionKind.number,
    inherits: true,
    min: 8,
    max: 200,
    step: 2,
  ),
  StyleProp(
    'fontWeight',
    'Letters',
    OptionKind.choice,
    inherits: true,
    choices: {'light': 'Light', 'medium': 'Medium', 'bold': 'Bold'},
  ),
  StyleProp(
    'textAlign',
    'Sits',
    OptionKind.choice,
    inherits: true,
    choices: {'left': 'Left', 'center': 'In the middle', 'right': 'Right'},
  ),
];

/// What anything that is a box takes: a pane, and whatever is placed in
/// one.
const boxStyle = [
  'background',
  'borderColor',
  'borderWidth',
  'radius',
  'padding',
  'opacity',
  'shadow',
];

/// What text takes, and so what anything that holds text hands down.
const textStyle = ['color', 'fontSize', 'fontWeight', 'textAlign'];

/// The properties called [keys], in the order they are listed above.
List<StyleProp> stylePropsOf(Iterable<String> keys) => [
  for (final prop in styleProps)
    if (keys.contains(prop.key)) prop,
];

/// Never throws: a look is decoration, so what is not a look is none.
Style styleFromJson(Object? json) => switch (json) {
  final Map<Object?, Object?> style => {
    for (final MapEntry(:key, :value) in style.entries)
      if (key is String && value != null) key: value,
  },
  _ => const {},
};

/// [style] with [values] set over it; one that is null is taken away,
/// which hands that property back to whatever is underneath.
Style withStyle(Style style, Style values) =>
    {...style, ...values}..removeWhere((_, value) => value == null);

/// What of [style] the things inside take after.
Style inheritedOf(Style style) => {
  for (final prop in styleProps)
    if (prop.inherits && style[prop.key] != null) prop.key: style[prop.key],
};

bool _written(Object? value) => value is String && value.contains('{{');

/// [style] as it stands now: a value written as a template
/// (`{{lamp.colour}}`) is what that reads as, among [scope] first.
Style readStyle(Watch watch, Style style, Map<String, Object?> scope) =>
    !style.values.any(_written)
    ? style
    : {
        for (final MapEntry(:key, :value) in style.entries)
          key: _written(value)
              ? readTemplate(watch, value as String, scope)
              : value,
      };
