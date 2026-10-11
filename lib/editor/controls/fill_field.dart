import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/colour_picker.dart';
import 'package:openlauncher/editor/controls/gradient_bar.dart';
import 'package:openlauncher/editor/controls/labelled_row.dart';
import 'package:openlauncher/editor/controls/slide_bar.dart';

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
                  ? 'Add colour'
                  : 'Add colour (gradient)',
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
          'Angle',
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
