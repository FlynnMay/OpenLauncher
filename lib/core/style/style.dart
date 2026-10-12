import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// A component's saved style: property name -> value.
typedef Style = Map<String, Object?>;

/// One style property, described as data for the editor.
class StyleProp extends ComponentOption {
  const StyleProp(
    super.key,
    super.label,
    super.kind, {
    this.inherits = false,
    super.defaultValue,
    super.choices,
    super.min,
    super.max,
    super.step,
    super.unset = 'Default',
  });

  /// Whether children inherit it unless they set their own.
  final bool inherits;
}

/// Every style property. A new one goes here, in the key list of whatever
/// takes it, and where it is drawn.
const styleProps = [
  StyleProp('background', 'Background', OptionKind.fill),
  StyleProp('borderColor', 'Border colour', OptionKind.colour),
  StyleProp(
    'borderWidth',
    'Border width',
    OptionKind.number,
    defaultValue: 2,
    max: 20,
    unset: null,
  ),
  StyleProp('radius', 'Corners', OptionKind.corners, max: 120, step: 2),
  StyleProp('padding', 'Padding', OptionKind.number, max: 80, step: 2),
  StyleProp(
    'opacity',
    'Opacity %',
    OptionKind.number,
    defaultValue: 100,
    max: 100,
    step: 5,
    unset: null,
  ),
  StyleProp(
    'shadow',
    'Shadow',
    OptionKind.number,
    defaultValue: 0,
    max: 60,
    step: 2,
    unset: null,
  ),
  StyleProp('color', 'Colour', OptionKind.colour, inherits: true),
  StyleProp(
    'fontSize',
    'Font size',
    OptionKind.number,
    inherits: true,
    min: 8,
    max: 200,
    step: 2,
  ),
  StyleProp(
    'fontWeight',
    'Font weight',
    OptionKind.choice,
    inherits: true,
    choices: {'light': 'Light', 'medium': 'Medium', 'bold': 'Bold'},
  ),
  StyleProp(
    'textAlign',
    'Text align',
    OptionKind.choice,
    inherits: true,
    choices: {'left': 'Left', 'center': 'Centre', 'right': 'Right'},
  ),
  // A pane's scroll bar. Read by `ScrollbarStyle.of`.
  StyleProp(
    'scrollbarSide',
    'Position',
    OptionKind.choice,
    defaultValue: 'end',
    choices: {'end': 'Right / bottom', 'start': 'Left / top'},
    unset: null,
  ),
  StyleProp(
    'scrollbarSize',
    'Thickness',
    OptionKind.number,
    defaultValue: 6,
    min: 1,
    max: 40,
    unset: null,
  ),
  StyleProp(
    'scrollbarLength',
    'Length %',
    OptionKind.number,
    defaultValue: 100,
    min: 5,
    max: 100,
    step: 5,
    unset: null,
  ),
  StyleProp(
    'scrollbarMargin',
    'Edge margin',
    OptionKind.number,
    defaultValue: 4,
    max: 80,
    unset: null,
  ),
  StyleProp(
    'scrollbarEndMargin',
    'End margin',
    OptionKind.number,
    defaultValue: 4,
    max: 200,
    step: 2,
    unset: null,
  ),
  StyleProp(
    'scrollbarOpacity',
    'Opacity %',
    OptionKind.number,
    defaultValue: 100,
    max: 100,
    step: 5,
    unset: null,
  ),
  StyleProp('scrollbarThumb', 'Thumb', OptionKind.fill),
  StyleProp('scrollbarThumbBorder', 'Thumb border colour', OptionKind.colour),
  StyleProp(
    'scrollbarThumbBorderWidth',
    'Thumb border width',
    OptionKind.number,
    defaultValue: 1,
    max: 20,
    unset: null,
  ),
  StyleProp(
    'scrollbarThumbRadius',
    'Thumb corners',
    OptionKind.number,
    max: 120,
    unset: 'Round',
  ),
  StyleProp(
    'scrollbarInset',
    'Thumb inset',
    OptionKind.number,
    defaultValue: 0,
    max: 20,
    unset: null,
  ),
  StyleProp(
    'scrollbarMinLength',
    'Thumb minimum length',
    OptionKind.number,
    defaultValue: 24,
    min: 4,
    max: 400,
    step: 4,
    unset: null,
  ),
  StyleProp('scrollbarTrack', 'Track', OptionKind.fill),
  StyleProp('scrollbarTrackBorder', 'Track border colour', OptionKind.colour),
  StyleProp(
    'scrollbarTrackBorderWidth',
    'Track border width',
    OptionKind.number,
    defaultValue: 1,
    max: 20,
    unset: null,
  ),
  StyleProp(
    'scrollbarTrackRadius',
    'Track corners',
    OptionKind.number,
    max: 120,
    unset: 'Round',
  ),
];

/// Properties of any box.
const boxStyle = [
  'background',
  'borderColor',
  'borderWidth',
  'radius',
  'padding',
  'opacity',
  'shadow',
];

/// Properties of a pane's scroll bar.
const scrollbarStyle = [
  'scrollbarSide',
  'scrollbarSize',
  'scrollbarLength',
  'scrollbarMargin',
  'scrollbarEndMargin',
  'scrollbarOpacity',
  'scrollbarThumb',
  'scrollbarThumbBorder',
  'scrollbarThumbBorderWidth',
  'scrollbarThumbRadius',
  'scrollbarInset',
  'scrollbarMinLength',
  'scrollbarTrack',
  'scrollbarTrackBorder',
  'scrollbarTrackBorderWidth',
  'scrollbarTrackRadius',
];

/// Text properties; containers pass these down.
const textStyle = ['color', 'fontSize', 'fontWeight', 'textAlign'];

/// The properties named [keys], in declaration order.
List<StyleProp> stylePropsOf(Iterable<String> keys) => [
  for (final prop in styleProps)
    if (keys.contains(prop.key)) prop,
];

/// Never throws; anything unreadable is an empty style.
Style styleFromJson(Object? json) => switch (json) {
  final Map<Object?, Object?> style => {
    for (final MapEntry(:key, :value) in style.entries)
      if (key is String && value != null) key: value,
  },
  _ => const {},
};

/// Merges [values] over [style]; null removes a property.
Style withStyle(Style style, Style values) =>
    {...style, ...values}..removeWhere((_, value) => value == null);

/// The inherited properties of [style].
Style inheritedOf(Style style) => {
  for (final prop in styleProps)
    if (prop.inherits && style[prop.key] != null) prop.key: style[prop.key],
};

bool _written(Object? value) => value is String && value.contains('{{');

/// [style] with template values evaluated, [scope] first.
Style readStyle(Watch watch, Style style, Map<String, Object?> scope) =>
    !style.values.any(_written)
    ? style
    : {
        for (final MapEntry(:key, :value) in style.entries)
          key: _written(value)
              ? readTemplate(watch, value as String, scope)
              : value,
      };
