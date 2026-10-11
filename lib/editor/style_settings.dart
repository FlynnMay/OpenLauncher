import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/gradient_bar.dart';
import 'package:openlauncher/editor/option_fields.dart';

/// The fields for the properties of a look called [keys], showing what
/// [style] has for each. A change is told as the property and what it is
/// to be, null for the usual again.
List<Widget> styleFields({
  required Iterable<String> keys,
  required Style style,
  required void Function(String key, Object? value) onChanged,
  double corner = 10,
}) => ruleFields(
  options: stylePropsOf(keys),
  json: style,
  onChanged: onChanged,
  corner: corner,
);

/// The look of one or more things, as far as they take the same
/// properties: with several, the first one's is shown, and a change is
/// made to that property of each, so that giving them the same border
/// leaves each its own background.
class StyleSettings extends StatelessWidget {
  const StyleSettings({
    super.key,
    required this.keys,
    required this.style,
    required this.onChanged,
    this.corner = 10,
  });

  /// The properties that mean something to what is being edited.
  final Iterable<String> keys;
  final Style style;
  final void Function(String key, Object? value) onChanged;

  /// How round its corners usually are.
  final double corner;

  @override
  Widget build(BuildContext context) => keys.isEmpty
      ? const SizedBox.shrink()
      : Section(
          'Style',
          styleFields(
            keys: keys,
            style: style,
            onChanged: onChanged,
            corner: corner,
          ),
        );
}

/// What a box is filled with: nothing, one colour, or several as a
/// gradient, with where along it each one sits and which way it runs.
class FillField extends StatelessWidget {
  const FillField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// As a look says it: see [BoxStyle.backgroundOf].
  final Object? value;
  final void Function(Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final fill = BoxStyle.of({'background': value});
    void set(List<int> colors, [List<double> stops = const [], int? angle]) =>
        onChanged(BoxStyle.backgroundOf(colors, stops, angle ?? fill.angle));
    if (fill.colors.length < 2) {
      return LabelledRow(
        label,
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final colour in fill.colors)
              ColourChip(colour: colour, onChanged: (next) => set([?next])),
            ColourChip(
              colour: null,
              tooltip: fill.colors.isEmpty
                  ? 'Give it a background colour'
                  : 'Add a colour, for a gradient',
              onChanged: (next) => set([...fill.colors, ?next]),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label),
        ),
        GradientBar(
          stops: [
            for (final (index, at) in fill.positions.indexed)
              (colour: fill.colors[index], at: at),
          ],
          max: BoxStyle.maxColors,
          onChanged: (stops) => set(
            [for (final stop in stops) stop.colour],
            [
              if (stops.length > 1)
                for (final stop in stops) stop.at,
            ],
          ),
        ),
        LabelledRow(
          'Direction',
          SlideBar(
            value: fill.angle * 1.0,
            max: 345,
            divisions: 23,
            label: (angle) => '${angle.round()}°',
            onChanged: (angle) => set(fill.colors, fill.stops, angle.round()),
          ),
        ),
      ],
    );
  }
}
