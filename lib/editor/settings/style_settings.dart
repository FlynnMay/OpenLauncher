import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/colour_picker.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/gradient_bar.dart';
import 'package:openlauncher/editor/option_fields.dart';

/// Generated fields for style [keys]. Reports one property and its new value,
/// null for the default.
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

/// Style of one or more things. With several, the first one's values show and
/// a change applies that property to each.
class StyleSettings extends StatelessWidget {
  const StyleSettings({
    super.key,
    required this.keys,
    required this.style,
    required this.onChanged,
    this.corner = 10,
  });

  final Iterable<String> keys;
  final Style style;
  final void Function(String key, Object? value) onChanged;

  /// Default corner radius.
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

/// A fill: none, one colour, or a gradient.
class FillField extends StatelessWidget {
  const FillField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// In saved form; see [BoxStyle.backgroundOf].
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
